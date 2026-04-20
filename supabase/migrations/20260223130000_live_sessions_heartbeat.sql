-- Live sessions heartbeat
--
-- Prevents “ghost lives” when the broadcaster app crashes.
-- Hosts (via Edge Function) update last_heartbeat_at periodically.

alter table public.live_sessions
  add column if not exists last_heartbeat_at timestamptz;

-- Backfill for currently live rows (best-effort).
update public.live_sessions
set last_heartbeat_at = coalesce(last_heartbeat_at, updated_at, started_at, now())
where is_live = true
  and last_heartbeat_at is null;

create index if not exists live_sessions_last_heartbeat_at_idx
  on public.live_sessions (last_heartbeat_at desc);

-- Optional helper for scheduled cleanup (call from a cron/scheduler as service role).
create or replace function public.end_stale_live_sessions(max_age_seconds integer default 45)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.live_sessions
  set is_live = false,
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where is_live = true
    and coalesce(last_heartbeat_at, updated_at, started_at) < now() - make_interval(secs => max_age_seconds);

  get diagnostics n = row_count;
  return n;
end;
$$;
