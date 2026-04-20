-- Compatibility layer for DJ mixes + live session tables and storage buckets.
-- Some environments (especially older consumer schemas) expect these objects.
-- This migration is idempotent and safe to apply on existing projects.

-- UUID helper
create extension if not exists pgcrypto;

-- 1) Legacy/compat tables

create table if not exists public.dj_users (
  id uuid primary key default gen_random_uuid(),
  dj_id text,
  user_id text,
  firebase_uid text,
  created_at timestamptz not null default now()
);

create index if not exists dj_users_dj_id_idx on public.dj_users (dj_id);
create index if not exists dj_users_firebase_uid_idx on public.dj_users (firebase_uid);
create index if not exists dj_users_created_at_idx on public.dj_users (created_at desc);

create unique index if not exists dj_users_dj_firebase_uid_unique
  on public.dj_users (dj_id, firebase_uid)
  where firebase_uid is not null and length(trim(firebase_uid)) > 0;

create unique index if not exists dj_users_dj_user_id_unique
  on public.dj_users (dj_id, user_id)
  where user_id is not null and length(trim(user_id)) > 0;

create table if not exists public.dj_mixes (
  id uuid primary key default gen_random_uuid(),
  dj_id text,
  title text,
  description text,
  audio_url text,
  audio_path text,
  cover_url text,
  cover_path text,
  duration_seconds integer,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_mixes_dj_id_idx on public.dj_mixes (dj_id);
create index if not exists dj_mixes_created_at_idx on public.dj_mixes (created_at desc);
create index if not exists dj_mixes_is_active_idx on public.dj_mixes (is_active);

create table if not exists public.dj_live_sessions (
  id uuid primary key default gen_random_uuid(),
  dj_id text,
  channel_name text,
  status text,
  started_at timestamptz,
  ended_at timestamptz,
  region text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_live_sessions_dj_id_idx on public.dj_live_sessions (dj_id);
create index if not exists dj_live_sessions_status_idx on public.dj_live_sessions (status);
create index if not exists dj_live_sessions_started_at_idx on public.dj_live_sessions (started_at desc);

-- Security posture: keep these locked down by default.
-- Service role can still access; app-facing access should be implemented deliberately.
alter table public.dj_users enable row level security;
alter table public.dj_mixes enable row level security;
alter table public.dj_live_sessions enable row level security;

do $$
begin
  -- deny-all policies (idempotent)
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='dj_users' and policyname='deny_all_dj_users'
  ) then
    create policy deny_all_dj_users on public.dj_users for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='dj_mixes' and policyname='deny_all_dj_mixes'
  ) then
    create policy deny_all_dj_mixes on public.dj_mixes for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='dj_live_sessions' and policyname='deny_all_dj_live_sessions'
  ) then
    create policy deny_all_dj_live_sessions on public.dj_live_sessions for all using (false) with check (false);
  end if;
end $$;

-- 2) Storage buckets
-- Note: storage schema exists on Supabase projects. These inserts are safe if the bucket already exists.
insert into storage.buckets (id, name, public)
values
  ('dj-avatars', 'dj-avatars', true),
  ('dj-mix-covers', 'dj-mix-covers', true),
  ('dj-mixes', 'dj-mixes', false)
on conflict (id) do nothing;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
