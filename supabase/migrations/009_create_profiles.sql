-- Create/fix `profiles` table for Firebase-Auth + Supabase DB usage.
--
-- Assumptions (MVP):
-- - Firebase UID is stored as TEXT in `profiles.id`.
-- - App stores structured JSON under `profiles.settings` and sometimes `profiles.social_links`.
--
-- SECURITY WARNING:
-- This makes `profiles` publicly readable and writable (anon).
-- Use ONLY for development/MVP.

create table if not exists public.profiles (
  id text primary key,

  email text,
  username text,
  display_name text,
  full_name text,
  avatar_url text,

  role text not null default 'artist',

  bio text,
  city text,
  country text,

  -- Used by the app for Settings main menu persistence.
  settings jsonb not null default '{}'::jsonb,

  -- Used by some older screens; keep for backward compatibility.
  social_links jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- If the table already existed, ensure required columns exist.
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists role text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists country text;
alter table public.profiles add column if not exists settings jsonb;
alter table public.profiles add column if not exists social_links jsonb;
alter table public.profiles add column if not exists created_at timestamptz;
alter table public.profiles add column if not exists updated_at timestamptz;
-- Defaults (best-effort on existing columns)
alter table public.profiles alter column role set default 'artist';
alter table public.profiles alter column settings set default '{}'::jsonb;
alter table public.profiles alter column social_links set default '{}'::jsonb;
alter table public.profiles alter column created_at set default now();
alter table public.profiles alter column updated_at set default now();
-- Ensure settings columns are non-null (best-effort)
update public.profiles set settings = '{}'::jsonb where settings is null;
update public.profiles set social_links = '{}'::jsonb where social_links is null;
-- MVP public RLS policies (anon) so the client can select/insert/update.
DO $$
BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    alter table public.profiles enable row level security;

    BEGIN
      drop policy if exists "public select profiles" on public.profiles;
      drop policy if exists "public insert profiles" on public.profiles;
      drop policy if exists "public update profiles" on public.profiles;
      drop policy if exists "public delete profiles" on public.profiles;
    EXCEPTION WHEN undefined_object THEN
      -- ignore
    END;

    create policy "public select profiles" on public.profiles
      for select using (true);

    create policy "public insert profiles" on public.profiles
      for insert with check (true);

    create policy "public update profiles" on public.profiles
      for update using (true) with check (true);

    create policy "public delete profiles" on public.profiles
      for delete using (true);
  END IF;
END $$;
