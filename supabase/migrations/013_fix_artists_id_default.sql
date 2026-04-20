-- Ensure `artists.id` has a DEFAULT so inserts without `id` succeed.
--
-- Symptom:
--   inserts fail because `artists.id` is NOT NULL and has no DEFAULT.
--
-- This migration (idempotent-ish):
--   - Ensures pgcrypto extension exists
--   - If public.artists.id exists and is uuid, sets default gen_random_uuid()
--   - If id is text, sets default gen_random_uuid()::text

create extension if not exists "pgcrypto";
DO $$
DECLARE
  id_type text;
BEGIN
  IF to_regclass('public.artists') IS NULL THEN
    RETURN;
  END IF;

  SELECT c.data_type
    INTO id_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'artists'
    AND c.column_name = 'id';

  IF id_type = 'uuid' THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.artists ALTER COLUMN id SET DEFAULT gen_random_uuid()';
    EXCEPTION WHEN others THEN
      NULL;
    END;
  ELSIF id_type = 'text' THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.artists ALTER COLUMN id SET DEFAULT (gen_random_uuid()::text)';
    EXCEPTION WHEN others THEN
      NULL;
    END;
  END IF;
END $$;
