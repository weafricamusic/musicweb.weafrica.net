-- Create/fix `artists` table for Firebase-Auth + Supabase DB usage.
--
-- Assumptions (MVP):
-- - Firebase UID is stored as TEXT in `artists.user_id`.
-- - The app may read/write different display-name columns depending on older schemas.
-- - RLS is opened for anon (dev/MVP only), similar to 007_public_media_table_rls_policies.sql.
--
-- SECURITY WARNING:
-- This makes `artists` publicly readable and writable (anon).
-- Use ONLY for development/MVP.

-- Needed for gen_random_uuid()
create extension if not exists "pgcrypto";
create table if not exists public.artists (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,

  -- Display name variants (keep for backward compatibility)
  name text,
  artist_name text,
  stage_name text,
  display_name text,
  full_name text,
  username text,
  title text,
  artist text,
  stage text,

  email text,
  bio text,
  genre text,

  followers integer not null default 0,
  approved boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- If the table already existed, ensure required columns exist.
alter table public.artists add column if not exists user_id text;
alter table public.artists add column if not exists name text;
alter table public.artists add column if not exists artist_name text;
alter table public.artists add column if not exists stage_name text;
alter table public.artists add column if not exists display_name text;
alter table public.artists add column if not exists full_name text;
alter table public.artists add column if not exists username text;
alter table public.artists add column if not exists title text;
alter table public.artists add column if not exists artist text;
alter table public.artists add column if not exists stage text;
alter table public.artists add column if not exists email text;
alter table public.artists add column if not exists bio text;
alter table public.artists add column if not exists genre text;
alter table public.artists add column if not exists followers integer;
alter table public.artists add column if not exists approved boolean;
alter table public.artists add column if not exists created_at timestamptz;
alter table public.artists add column if not exists updated_at timestamptz;
-- Defaults (best-effort on existing columns)
alter table public.artists alter column followers set default 0;
alter table public.artists alter column approved set default false;
alter table public.artists alter column created_at set default now();
alter table public.artists alter column updated_at set default now();
-- Unique constraint for upserts on Firebase UID.
DO $$
BEGIN
  BEGIN
    alter table public.artists add constraint artists_user_id_key unique (user_id);
  EXCEPTION
    WHEN duplicate_table THEN
      -- relation/index name already exists
      NULL;
    WHEN duplicate_object THEN
      -- already exists
      NULL;
    WHEN unique_violation THEN
      -- duplicates exist; constraint cannot be added until cleaned up
      NULL;
  END;
END $$;
-- MVP public RLS policies (anon) so the client can select/insert/update.
DO $$
BEGIN
  IF to_regclass('public.artists') IS NOT NULL THEN
    alter table public.artists enable row level security;

    BEGIN
      drop policy if exists "public select artists" on public.artists;
      drop policy if exists "public insert artists" on public.artists;
      drop policy if exists "public update artists" on public.artists;
      drop policy if exists "public delete artists" on public.artists;
    EXCEPTION WHEN undefined_object THEN
      -- ignore
    END;

    create policy "public select artists" on public.artists
      for select using (true);

    create policy "public insert artists" on public.artists
      for insert with check (true);

    create policy "public update artists" on public.artists
      for update using (true) with check (true);

    create policy "public delete artists" on public.artists
      for delete using (true);
  END IF;
END $$;
