-- Fix `artists.user_id` type mismatch (UUID vs Firebase UID) and unblock inserts.
--
-- Symptom in app:
--   Artist creation fails (often due to invalid UUID for user_id, or RLS).
--
-- Root cause:
--   Many Supabase starter schemas use UUID + FK to auth.users, but this app uses
--   Firebase Auth UID strings.
--
-- This migration (idempotent-ish):
-- 1) Drops FK constraints ON public.artists (including any auth.users FK).
-- 2) Converts `public.artists.user_id` from UUID -> TEXT if needed.
-- 3) Ensures UNIQUE(user_id) (best-effort).
-- 4) Ensures MVP public RLS policies exist (anon select/insert/update/delete).
--
-- NOTE:
--   If other tables reference artists.user_id as UUID, you must update them too.

DO $$
DECLARE
  user_id_type text;
  fk record;
BEGIN
  IF to_regclass('public.artists') IS NULL THEN
    RETURN;
  END IF;

  -- 1) Drop FK constraints defined ON public.artists.
  FOR fk IN (
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.artists'::regclass
      AND c.contype = 'f'
  ) LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.artists DROP CONSTRAINT IF EXISTS %I', fk.conname);
    EXCEPTION WHEN others THEN
      NULL;
    END;
  END LOOP;

  -- 2) Convert artists.user_id UUID -> TEXT if needed
  SELECT c.data_type
    INTO user_id_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'artists'
    AND c.column_name = 'user_id';

  IF user_id_type = 'uuid' THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.artists ALTER COLUMN user_id DROP DEFAULT';
    EXCEPTION WHEN others THEN
      NULL;
    END;

    EXECUTE 'ALTER TABLE public.artists ALTER COLUMN user_id TYPE text USING user_id::text';
  END IF;

  -- 3) Best-effort unique constraint for upserts
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'public.artists'::regclass
      AND c.conname = 'artists_user_id_key'
  ) THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.artists ADD CONSTRAINT artists_user_id_key UNIQUE (user_id)';
    EXCEPTION
      WHEN duplicate_object THEN NULL;
      WHEN duplicate_table THEN NULL; -- 42P07: relation already exists (index name collision)
      WHEN unique_violation THEN NULL;
    END;
  END IF;

  -- 4) MVP RLS policies
  alter table public.artists enable row level security;

  BEGIN
    drop policy if exists "public select artists" on public.artists;
    drop policy if exists "public insert artists" on public.artists;
    drop policy if exists "public update artists" on public.artists;
    drop policy if exists "public delete artists" on public.artists;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

  create policy "public select artists" on public.artists
    for select using (true);

  create policy "public insert artists" on public.artists
    for insert with check (true);

  create policy "public update artists" on public.artists
    for update using (true) with check (true);

  create policy "public delete artists" on public.artists
    for delete using (true);
END $$;
