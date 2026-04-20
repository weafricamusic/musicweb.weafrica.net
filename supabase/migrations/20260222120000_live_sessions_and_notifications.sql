-- Consumer Live notifications + live presence
--
-- Goals:
-- - Provide a real-time table (`live_sessions`) for the consumer Live tab.
-- - Provide a subscriber registry (`live_notifications`) for "Notify me".
-- - Keep client access read-only for live sessions (live rows only).
-- - Writes happen via Edge API (service role).

-- Ensure uuid generator exists.
-- Supabase typically has pgcrypto enabled; keep this best-effort.
do $$
begin
  begin
    create extension if not exists pgcrypto;
  exception when insufficient_privilege then
    -- ignore
  end;
end $$;

-- Live sessions (realtime, read-only for clients).
create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  channel_id text not null,
  host_id text not null,
  host_name text,
  title text,
  is_live boolean not null default false,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Back-compat: if a legacy `live_sessions` table already exists (different columns),
-- ensure `channel_id` exists before creating indexes/policies below.
alter table public.live_sessions
  add column if not exists channel_id text;

-- Ensure required columns exist for indexes/policies used by the consumer Live tab.
alter table public.live_sessions
  add column if not exists host_id text,
  add column if not exists host_name text,
  add column if not exists title text,
  add column if not exists is_live boolean not null default false,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

do $$
declare
  has_channel boolean;
  has_agora_channel boolean;
  has_host_id boolean;
  has_artist_id boolean;
begin
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'live_sessions' and column_name = 'channel'
  ) into has_channel;
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'live_sessions' and column_name = 'agora_channel'
  ) into has_agora_channel;
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'live_sessions' and column_name = 'host_id'
  ) into has_host_id;
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'live_sessions' and column_name = 'artist_id'
  ) into has_artist_id;

  -- Normalize empty strings to NULL to avoid duplicate '' values breaking unique index creation.
  update public.live_sessions
    set channel_id = null
  where channel_id is not null
    and length(btrim(channel_id)) = 0;

  -- Backfill from legacy columns if present.
  if has_channel then
    execute 'update public.live_sessions '
      'set channel_id = nullif(btrim(channel::text), '''') '
      'where (channel_id is null or length(btrim(channel_id)) = 0) '
      'and channel is not null';
  end if;

  if has_agora_channel then
    execute 'update public.live_sessions '
      'set channel_id = nullif(btrim(agora_channel::text), '''') '
      'where (channel_id is null or length(btrim(channel_id)) = 0) '
      'and agora_channel is not null';
  end if;

  -- Preferred computed channel format used throughout the app.
  if has_host_id then
    execute 'update public.live_sessions '
      'set channel_id = ''weafrica_live_'' || btrim(host_id::text) '
      'where (channel_id is null or length(btrim(channel_id)) = 0) '
      'and host_id is not null and length(btrim(host_id::text)) > 0';
  elsif has_artist_id then
    execute 'update public.live_sessions '
      'set channel_id = ''weafrica_live_'' || btrim(artist_id::text) '
      'where (channel_id is null or length(btrim(channel_id)) = 0) '
      'and artist_id is not null and length(btrim(artist_id::text)) > 0';
  end if;
end $$;

-- One active row per channel.
create unique index if not exists live_sessions_channel_id_key
  on public.live_sessions (channel_id);
create index if not exists live_sessions_is_live_idx
  on public.live_sessions (is_live);
create index if not exists live_sessions_started_at_idx
  on public.live_sessions (started_at desc);

alter table public.live_sessions enable row level security;

do $$
begin
  -- Allow anyone to read only the rows that are live.
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'public_select_live_sessions_live_only'
  ) then
    create policy public_select_live_sessions_live_only
      on public.live_sessions
      for select
      using (is_live = true);
  end if;

  -- Deny all writes from client roles (writes happen via service role / Edge API).
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'deny_all_live_sessions'
  ) then
    create policy deny_all_live_sessions
      on public.live_sessions
      for all
      using (false)
      with check (false);
  end if;
end $$;

grant select on table public.live_sessions to anon, authenticated;

-- Ensure the table is available for Supabase Realtime.
do $$
begin
  begin
    alter publication supabase_realtime add table public.live_sessions;
  exception when duplicate_object then
    -- already added
  when undefined_object then
    -- publication might not exist in some local setups
    null;
  end;
end $$;

-- Notify-me subscribers.
create table if not exists public.live_notifications (
  id uuid primary key default gen_random_uuid(),
  user_uid text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists live_notifications_user_uid_key
  on public.live_notifications (user_uid);

alter table public.live_notifications enable row level security;

do $$
begin
  -- Default: deny all access from client roles (Edge API writes + reads).
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_notifications'
      and policyname = 'deny_all_live_notifications'
  ) then
    create policy deny_all_live_notifications
      on public.live_notifications
      for all
      using (false)
      with check (false);
  end if;
end $$;
