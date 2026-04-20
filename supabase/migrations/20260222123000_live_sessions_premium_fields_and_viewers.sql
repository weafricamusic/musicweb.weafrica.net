-- Premium Live session fields + realtime viewer count
--
-- Adds fields required by the consumer premium Live cards:
-- - artist_id (alias of host_id for clarity)
-- - thumbnail_url
-- - category
-- - viewer_count (realtime)
--
-- Adds RPC helpers to increment viewer_count from the client.

alter table public.live_sessions
  add column if not exists artist_id text,
  add column if not exists thumbnail_url text,
  add column if not exists category text,
  add column if not exists viewer_count integer not null default 0;

-- Backfill for existing rows.
update public.live_sessions
set viewer_count = 0
where viewer_count is null;

-- Convenience: keep artist_id aligned for existing rows.
update public.live_sessions
set artist_id = host_id
where (artist_id is null or artist_id = '')
  and host_id is not null
  and host_id <> '';

create index if not exists live_sessions_viewer_count_idx
  on public.live_sessions (viewer_count desc);

-- Increment viewer count by live session id.
create or replace function public.increment_viewer(live_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.live_sessions
  set viewer_count = coalesce(viewer_count, 0) + 1,
      updated_at = now()
  where id = live_id
    and is_live = true;
end;
$$;

-- Increment viewer count by channel id (useful for push deep links).
create or replace function public.increment_viewer_by_channel(channel_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.live_sessions
  set viewer_count = coalesce(viewer_count, 0) + 1,
      updated_at = now()
  where live_sessions.channel_id = increment_viewer_by_channel.channel_id
    and is_live = true;
end;
$$;

grant execute on function public.increment_viewer(uuid) to anon, authenticated;
grant execute on function public.increment_viewer_by_channel(text) to anon, authenticated;
