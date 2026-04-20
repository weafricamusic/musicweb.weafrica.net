-- Live streams control plane for admin moderation.
-- Service-role bypasses RLS; normal clients are denied by default.

-- Some environments may already have a VIEW named `public.live_streams`.
-- We need a real table for moderation updates, so rename any existing view out of the way.
do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'live_streams'
      and c.relkind in ('v','m')
  ) then
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'live_streams_legacy_view'
    ) then
      execute 'alter view public.live_streams rename to live_streams_legacy_view';
    else
      execute 'alter view public.live_streams rename to live_streams_legacy_view_20260111';
    end if;
  end if;
end $$;
create table if not exists public.live_streams (
  id bigserial primary key,
  channel_name text not null,
  host_id text,
  host_firebase_uid text,
  host_type text not null check (host_type in ('dj','artist')),
  stream_type text not null default 'dj_live' check (stream_type in ('dj_live','artist_live','battle')),
  status text not null default 'live' check (status in ('live','ended')),
  viewer_count integer not null default 0,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  region text not null default 'MW',
  ended_reason text,
  ended_by_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists live_streams_status_idx on public.live_streams (status);
create index if not exists live_streams_region_idx on public.live_streams (region);
create index if not exists live_streams_started_at_idx on public.live_streams (started_at desc);
create index if not exists live_streams_host_idx on public.live_streams (host_type, host_id);
create index if not exists live_streams_host_firebase_uid_idx on public.live_streams (host_firebase_uid);
create index if not exists live_streams_channel_name_idx on public.live_streams (channel_name);
alter table public.live_streams enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_streams'
      and policyname = 'deny_all_live_streams'
  ) then
    create policy deny_all_live_streams
      on public.live_streams
      for all
      using (false)
      with check (false);
  end if;
end $$;
