-- Live Analytics (watch time heartbeats)
--
-- Goal:
-- - Estimate watch time via periodic client heartbeats.
-- - Keep writes server-authenticated (Edge function with Firebase auth).
-- - Support aggregation for an admin analytics dashboard.
--
-- Notes:
-- - This project uses Firebase UIDs (text) in DB.

create extension if not exists pgcrypto;

create table if not exists public.live_watch_heartbeats (
  id uuid primary key default gen_random_uuid(),

  live_id uuid not null references public.live_sessions(id) on delete cascade,
  channel_id text not null,
  user_id text not null,

  -- Minute bucket for idempotent upserts.
  bucket timestamptz not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  meta jsonb not null default '{}'::jsonb
);

create unique index if not exists live_watch_heartbeats_live_user_bucket_key
  on public.live_watch_heartbeats (live_id, user_id, bucket);

create index if not exists live_watch_heartbeats_live_bucket_idx
  on public.live_watch_heartbeats (live_id, bucket desc);

alter table public.live_watch_heartbeats enable row level security;

-- Default: deny all client access; Edge function uses service role.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_watch_heartbeats'
      and policyname = 'deny_all_live_watch_heartbeats'
  ) then
    create policy deny_all_live_watch_heartbeats
      on public.live_watch_heartbeats
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Admin aggregation RPC (not granted to anon/authenticated).
-- Returns per-session metrics for the last N days.
create or replace function public.get_live_analytics_overview(p_days int default 7)
returns table (
  live_id uuid,
  channel_id text,
  host_id text,
  host_name text,
  title text,
  started_at timestamptz,
  ended_at timestamptz,
  is_live boolean,
  viewer_count int,
  chat_messages bigint,
  gifts_count bigint,
  coins_spent bigint,
  watch_minutes_estimate bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  since_ts timestamptz;
begin
  since_ts := now() - make_interval(days => greatest(1, least(90, coalesce(p_days, 7))));

  return query
  with sessions as (
    select s.*
    from public.live_sessions s
    where coalesce(s.started_at, s.created_at) >= since_ts
  ),
  chat as (
    select m.live_id, count(*)::bigint as chat_messages
    from public.live_messages m
    join sessions s on s.id = m.live_id
    where m.created_at >= since_ts
    group by m.live_id
  ),
  gifts as (
    select s.id as live_id,
           count(*)::bigint as gifts_count,
           coalesce(sum(e.coin_cost), 0)::bigint as coins_spent
    from sessions s
    join public.live_gift_events e
      on e.channel_id = s.channel_id
     and e.created_at >= coalesce(s.started_at, s.created_at)
     and e.created_at <= coalesce(s.ended_at, now())
    group by s.id
  ),
  watch as (
    -- Each unique bucket ~= 1 minute watched.
    select h.live_id, count(*)::bigint as watch_minutes_estimate
    from public.live_watch_heartbeats h
    join sessions s on s.id = h.live_id
    where h.bucket >= since_ts
    group by h.live_id
  )
  select
    s.id as live_id,
    s.channel_id,
    s.host_id,
    s.host_name,
    s.title,
    s.started_at,
    s.ended_at,
    s.is_live,
    coalesce(s.viewer_count, 0) as viewer_count,
    coalesce(c.chat_messages, 0) as chat_messages,
    coalesce(g.gifts_count, 0) as gifts_count,
    coalesce(g.coins_spent, 0) as coins_spent,
    coalesce(w.watch_minutes_estimate, 0) as watch_minutes_estimate
  from sessions s
  left join chat c on c.live_id = s.id
  left join gifts g on g.live_id = s.id
  left join watch w on w.live_id = s.id
  order by coalesce(s.started_at, s.created_at) desc;
end;
$$;

notify pgrst, 'reload schema';
