-- Fix `profiles.id` type mismatch (UUID vs Firebase UID).
--
-- Symptom:
--   invalid input syntax for type uuid: "<firebase_uid>"
--
-- Root cause:
--   The app uses Firebase Auth, so it writes Firebase UID strings into `profiles.id`.
--   If your existing `profiles.id` column is UUID, inserts/updates will fail.
--
-- What this migration does (idempotent):
--   If `public.profiles.id` is UUID, convert it to TEXT and drop any UUID default.
--
-- Note:
--   If you have foreign keys referencing `profiles.id` as UUID, you must update those
--   references as well. This repo's migrations do not define such FKs.

DO $$
DECLARE
  id_type text;
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RETURN;
  END IF;

  SELECT c.data_type
    INTO id_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'profiles'
    AND c.column_name = 'id';

  IF id_type = 'uuid' THEN
    -- Drop any UUID default like gen_random_uuid()
    BEGIN
      EXECUTE 'ALTER TABLE public.profiles ALTER COLUMN id DROP DEFAULT';
    EXCEPTION WHEN others THEN
      -- ignore
      NULL;
    END;

    -- Convert UUID -> TEXT
    EXECUTE 'ALTER TABLE public.profiles ALTER COLUMN id TYPE text USING id::text';
  END IF;
END $$;
