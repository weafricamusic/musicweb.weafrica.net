-- Live sessions scheduling table.
-- Some dashboards/clients expect `public.live_sessions` to exist for scheduling and moderation.
-- This migration is idempotent and safe across projects.

create extension if not exists pgcrypto;

-- If a view exists with this name, move it aside so we can create the table.
do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'live_sessions'
      and c.relkind in ('v','m')
  ) then
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'live_sessions_legacy_view'
    ) then
      execute 'alter view public.live_sessions rename to live_sessions_legacy_view';
    else
      execute 'alter view public.live_sessions rename to live_sessions_legacy_view_20260216';
    end if;
  end if;
end $$;

create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),

  -- A stable identifier to connect to streaming infra (e.g. Agora channel).
  channel_name text,

  host_type text not null default 'dj' check (host_type in ('dj','artist')),
  host_id text,
  host_firebase_uid text,

  stream_type text not null default 'dj_live' check (stream_type in ('dj_live','artist_live','battle')),

  title text,
  description text,

  status text not null default 'scheduled' check (status in ('scheduled','live','ended','canceled')),

  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,

  region text not null default 'MW',
  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If the table already existed in a legacy environment, ensure required columns exist
-- before creating indexes/policies.
alter table if exists public.live_sessions
  add column if not exists channel_name text,
  add column if not exists host_type text,
  add column if not exists host_id text,
  add column if not exists host_firebase_uid text,
  add column if not exists stream_type text,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists status text,
  add column if not exists scheduled_start_at timestamptz,
  add column if not exists scheduled_end_at timestamptz,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists region text,
  add column if not exists meta jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- Best-effort defaults for legacy rows.
update public.live_sessions set region = coalesce(region, 'MW') where region is null;
update public.live_sessions set meta = coalesce(meta, '{}'::jsonb) where meta is null;
update public.live_sessions set status = coalesce(status, 'scheduled') where status is null;
update public.live_sessions set host_type = coalesce(host_type, 'dj') where host_type is null;
update public.live_sessions set stream_type = coalesce(stream_type, 'dj_live') where stream_type is null;
update public.live_sessions set created_at = coalesce(created_at, now()) where created_at is null;
update public.live_sessions set updated_at = coalesce(updated_at, now()) where updated_at is null;

alter table public.live_sessions alter column region set default 'MW';
alter table public.live_sessions alter column meta set default '{}'::jsonb;
alter table public.live_sessions alter column status set default 'scheduled';
alter table public.live_sessions alter column host_type set default 'dj';
alter table public.live_sessions alter column stream_type set default 'dj_live';
alter table public.live_sessions alter column created_at set default now();
alter table public.live_sessions alter column updated_at set default now();

-- Best-effort constraints (avoid failing if legacy data violates them).
do $$
begin
  begin
    alter table public.live_sessions
      add constraint live_sessions_host_type_check
      check (host_type in ('dj','artist'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.live_sessions
      add constraint live_sessions_stream_type_check
      check (stream_type in ('dj_live','artist_live','battle'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.live_sessions
      add constraint live_sessions_status_check
      check (status in ('scheduled','live','ended','canceled'));
  exception when duplicate_object then null;
  end;
end $$;

create index if not exists live_sessions_status_idx on public.live_sessions (status);
create index if not exists live_sessions_region_idx on public.live_sessions (region);
create index if not exists live_sessions_scheduled_start_idx on public.live_sessions (scheduled_start_at desc);
create index if not exists live_sessions_started_at_idx on public.live_sessions (started_at desc);
create index if not exists live_sessions_host_idx on public.live_sessions (host_type, host_id);
create index if not exists live_sessions_host_firebase_uid_idx on public.live_sessions (host_firebase_uid);
create index if not exists live_sessions_channel_name_idx on public.live_sessions (channel_name);

alter table public.live_sessions enable row level security;

do $$
begin
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

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
