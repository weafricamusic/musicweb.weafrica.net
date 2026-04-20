-- Fix `profiles.id` type mismatch (UUID vs Firebase UID) when an auth.users FK exists.
--
-- Your Supabase project likely started with the default schema:
--   profiles.id UUID PRIMARY KEY REFERENCES auth.users(id)
--
-- This app uses Firebase Auth, so it needs:
--   profiles.id TEXT (Firebase UID)
--
-- This migration (idempotent-ish):
-- 1) Drops foreign keys on `public.profiles` (including the default `profiles_id_fkey`).
-- 2) Drops any UUID default on `profiles.id`.
-- 3) Converts `profiles.id` from UUID -> TEXT.
--
-- NOTE: If you have other tables that reference `profiles.id` as UUID, you must
-- also convert those referencing columns to TEXT (or rebuild the FKs).

DO $$
DECLARE
  id_type text;
  fk record;
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RETURN;
  END IF;

  -- 1) Drop FK constraints defined ON public.profiles.
  -- This includes the common default FK: profiles.id -> auth.users.id
  FOR fk IN (
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.profiles'::regclass
      AND c.contype = 'f'
  ) LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS %I', fk.conname);
    EXCEPTION WHEN others THEN
      NULL;
    END;
  END LOOP;

  -- 2) If profiles.id is UUID, drop default and convert to TEXT.
  SELECT c.data_type
    INTO id_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'profiles'
    AND c.column_name = 'id';

  IF id_type = 'uuid' THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.profiles ALTER COLUMN id DROP DEFAULT';
    EXCEPTION WHEN others THEN
      NULL;
    END;

    EXECUTE 'ALTER TABLE public.profiles ALTER COLUMN id TYPE text USING id::text';
  END IF;
END $$;
