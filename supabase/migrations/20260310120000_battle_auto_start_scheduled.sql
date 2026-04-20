-- Auto-start scheduled battles (scheduled_at → live)
--
-- Purpose:
-- - When a battle has a future `scheduled_at` and is accepted by the opponent,
--   automatically flip it to `status='live'` once the scheduled time arrives.
-- - Mirror into `public.live_sessions` so the consumer Live tab can discover it.
--
-- Notes:
-- - Best-effort and safe to run frequently (idempotent).
-- - Also performs a lightweight cleanup: expired pending invites are marked
--   `expired`, and any unaccepted scheduled battles have `scheduled_at` cleared
--   so they disappear from the consumer UPCOMING list.
--
-- How it runs:
-- - Exposes `public.auto_start_due_scheduled_battles(max_to_start)` (service_role).
-- - Optionally schedules it every minute via `pg_cron` (no-ops if unavailable).

-- Ensure live_sessions has the columns we upsert (best-effort, back-compat).
alter table public.live_sessions
  add column if not exists artist_id text,
  add column if not exists thumbnail_url text,
  add column if not exists category text,
  add column if not exists viewer_count integer not null default 0,
  add column if not exists last_heartbeat_at timestamptz;

-- Ensure live_battles has scheduling metadata (Step 8 is preferred).
alter table public.live_battles
  add column if not exists duration_seconds integer,
  add column if not exists scheduled_at timestamptz,
  add column if not exists title text,
  add column if not exists category text,
  add column if not exists ends_at timestamptz;

create or replace function public.auto_start_due_scheduled_battles(max_to_start integer default 50)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  lim integer;
  n integer;
begin
  lim := greatest(1, least(coalesce(max_to_start, 50), 200));

  -- Cleanup: expire stale pending invites and hide unaccepted scheduled battles.
  begin
    with expired as (
      update public.battle_invites bi
      set status = 'expired',
          responded_at = coalesce(bi.responded_at, now())
      where bi.status = 'pending'
        and bi.responded_at is null
        and bi.expires_at <= now()
      returning bi.battle_id
    )
    update public.live_battles b
    set scheduled_at = null
    from expired e
    where b.battle_id = e.battle_id
      and b.scheduled_at is not null
      and b.status <> 'live'
      and b.status <> 'ended';
  exception
    when undefined_table then null;
    when undefined_column then null;
    when insufficient_privilege then null;
    when others then null;
  end;

  with due as (
    select
      b.battle_id,
      b.channel_id,
      b.host_a_id,
      b.host_b_id,
      greatest(60, least(coalesce(b.duration_seconds, 30 * 60), 6 * 3600)) as duration_seconds,
      nullif(btrim(coalesce(b.title, '')), '') as battle_title,
      coalesce(nullif(btrim(coalesce(pa.display_name, pa.full_name, pa.username, '')), ''), b.host_a_id, 'Host A') as host_a_name,
      coalesce(nullif(btrim(coalesce(pb.display_name, pb.full_name, pb.username, '')), ''), b.host_b_id, 'Host B') as host_b_name,
      nullif(btrim(coalesce(pa.avatar_url, '')), '') as host_a_thumb,
      coalesce(
        nullif(btrim(coalesce(b.title, '')), ''),
        coalesce(nullif(btrim(coalesce(pa.display_name, pa.full_name, pa.username, '')), ''), b.host_a_id, 'Host A')
          || ' vs ' ||
        coalesce(nullif(btrim(coalesce(pb.display_name, pb.full_name, pb.username, '')), ''), b.host_b_id, 'Host B')
      ) as title_text,
      coalesce(nullif(btrim(b.host_a_id), ''), nullif(btrim(b.host_b_id), '')) as primary_host_id
    from public.live_battles b
    left join public.profiles pa on pa.id = b.host_a_id
    left join public.profiles pb on pb.id = b.host_b_id
    where b.scheduled_at is not null
      and b.scheduled_at <= now()
      and b.status <> 'live'
      and b.status <> 'ended'
      and exists (
        select 1
        from public.battle_invites bi
        where bi.battle_id = b.battle_id
          and bi.status = 'accepted'
      )
    order by b.scheduled_at asc
    limit lim
    for update of b skip locked
  ),
  started as (
    update public.live_battles b
    set status = 'live',
        started_at = coalesce(b.started_at, now()),
        ends_at = coalesce(b.ends_at, now() + make_interval(secs => due.duration_seconds)),
        ended_at = null,
        host_a_ready = true,
        host_b_ready = true
    from due
    where b.battle_id = due.battle_id
      and b.status <> 'live'
      and b.status <> 'ended'
    returning b.battle_id, b.channel_id, b.started_at
  ),
  upserted as (
    insert into public.live_sessions (
      channel_id,
      host_id,
      artist_id,
      host_name,
      thumbnail_url,
      category,
      title,
      viewer_count,
      is_live,
      started_at,
      last_heartbeat_at,
      ended_at,
      updated_at
    )
    select
      due.channel_id,
      due.primary_host_id,
      due.primary_host_id,
      due.host_a_name,
      due.host_a_thumb,
      'battle',
      due.title_text,
      0,
      true,
      started.started_at,
      started.started_at,
      null,
      started.started_at
    from due
    join started on started.battle_id = due.battle_id
    on conflict (channel_id) do update
      set is_live = true,
          host_id = excluded.host_id,
          artist_id = excluded.artist_id,
          host_name = excluded.host_name,
          thumbnail_url = excluded.thumbnail_url,
          category = excluded.category,
          title = excluded.title,
          started_at = excluded.started_at,
          last_heartbeat_at = excluded.last_heartbeat_at,
          ended_at = null,
          updated_at = excluded.updated_at
  )
  select count(*) into n from started;

  return coalesce(n, 0);
end;
$$;

revoke all on function public.auto_start_due_scheduled_battles(integer) from public;
grant execute on function public.auto_start_due_scheduled_battles(integer) to service_role;

-- Optional: run every minute via pg_cron.
-- Best-effort and will no-op if pg_cron isn't available.
do $$
declare
  has_pg_cron boolean;
begin
  begin
    create extension if not exists pg_cron;
  exception
    when insufficient_privilege then null;
    when undefined_file then null;
  end;

  select exists(
    select 1
    from pg_extension
    where extname = 'pg_cron'
  ) into has_pg_cron;

  if has_pg_cron then
    begin
      if not exists (
        select 1
        from cron.job
        where jobname = 'battle_auto_start_scheduled_1m'
      ) then
        perform cron.schedule(
          'battle_auto_start_scheduled_1m',
          '* * * * *',
          'select public.auto_start_due_scheduled_battles(50);'
        );
      end if;
    exception
      when undefined_table then null;
      when undefined_function then null;
      when undefined_column then null;
      when invalid_schema_name then null;
      when insufficient_privilege then null;
      when others then null;
    end;
  end if;
end $$;