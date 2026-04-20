-- STEP 4 — Ready → Countdown → Live
-- Adds battle states: ready, countdown
-- Adds ends_at (scheduled end time) separate from ended_at (actual end time)

-- 1) Schema updates
alter table public.live_battles
  add column if not exists ends_at timestamptz;
-- Normalize any null/legacy values
update public.live_battles
set status = coalesce(nullif(trim(status), ''), 'waiting')
where status is null or length(trim(status)) = 0;
-- Drop any existing status check constraint (name may vary)
do $$
declare
  c text;
begin
  select con.conname into c
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'live_battles'
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) ilike '%status%'
    and pg_get_constraintdef(con.oid) ilike '%waiting%';

  if c is not null then
    execute format('alter table public.live_battles drop constraint %I', c);
  end if;
end $$;
alter table public.live_battles
  add constraint live_battles_status_check
  check (status in ('waiting','ready','countdown','live','ended'));
-- 2) RPCs (service_role only)

-- Set ready/unready for a host.
-- waiting (none ready) → ready (one ready) → countdown (both ready)
create or replace function public.battle_set_ready(
  p_battle_id text,
  p_user_id text,
  p_ready boolean
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  ready boolean := coalesce(p_ready, true);
  next_status text;
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  if b.status = 'ended' then
    raise exception 'battle_ended';
  end if;
  if b.status = 'live' then
    raise exception 'battle_live';
  end if;

  if b.host_a_id = trim(p_user_id) then
    update public.live_battles
      set host_a_ready = ready
    where battle_id = trim(p_battle_id)
    returning * into b;
  elsif b.host_b_id = trim(p_user_id) then
    update public.live_battles
      set host_b_ready = ready
    where battle_id = trim(p_battle_id)
    returning * into b;
  else
    raise exception 'not_a_host';
  end if;

  if b.host_a_ready and b.host_b_ready then
    next_status := 'countdown';
  elsif b.host_a_ready or b.host_b_ready then
    next_status := 'ready';
  else
    next_status := 'waiting';
  end if;

  update public.live_battles
    set status = next_status
  where battle_id = trim(p_battle_id)
  returning * into b;

  return b;
end;
$$;
-- Start battle after countdown (client-driven).
create or replace function public.battle_start(
  p_battle_id text,
  p_user_id text,
  p_duration_seconds integer
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  dur integer := coalesce(p_duration_seconds, 1200);
  now_ts timestamptz := now();
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  dur := greatest(60, least(dur, 6 * 3600));

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  if not (b.host_a_id = trim(p_user_id) or b.host_b_id = trim(p_user_id)) then
    raise exception 'not_a_host';
  end if;

  if b.status = 'ended' then
    raise exception 'battle_ended';
  end if;

  if b.status = 'live' then
    return b;
  end if;

  if not (b.host_a_ready and b.host_b_ready) then
    raise exception 'not_ready';
  end if;

  update public.live_battles
    set status = 'live',
        started_at = now_ts,
        ends_at = now_ts + make_interval(secs => dur),
        ended_at = null
  where battle_id = trim(p_battle_id)
  returning * into b;

  return b;
end;
$$;
-- End battle (host-driven; used for timer end or host-leave safety).
create or replace function public.battle_end(
  p_battle_id text,
  p_user_id text,
  p_reason text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  now_ts timestamptz := now();
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  if not (b.host_a_id = trim(p_user_id) or b.host_b_id = trim(p_user_id)) then
    raise exception 'not_a_host';
  end if;

  if b.status = 'ended' then
    return b;
  end if;

  update public.live_battles
    set status = 'ended',
        ends_at = coalesce(ends_at, now_ts),
        ended_at = coalesce(ended_at, now_ts)
  where battle_id = trim(p_battle_id)
  returning * into b;

  return b;
end;
$$;
revoke all on function public.battle_set_ready(text, text, boolean) from public;
revoke all on function public.battle_start(text, text, integer) from public;
revoke all on function public.battle_end(text, text, text) from public;
grant execute on function public.battle_set_ready(text, text, boolean) to service_role;
grant execute on function public.battle_start(text, text, integer) to service_role;
grant execute on function public.battle_end(text, text, text) to service_role;
