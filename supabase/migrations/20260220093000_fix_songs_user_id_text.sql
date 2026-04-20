-- Fix `songs.user_id` type mismatch (UUID vs Firebase UID).
--
-- Symptom:
--   invalid input syntax for type uuid: "<firebase_uid>"
--
-- Root cause:
--   The app uses Firebase Auth, so it writes Firebase UID strings into `songs.user_id`.
--   Some older/manual schemas created `songs.user_id` as UUID (often referencing auth.users).
--
-- What this migration does (idempotent):
--   - If public.songs.user_id is UUID, drop any FK constraints on songs.user_id (best-effort)
--     then convert it to TEXT and drop any UUID default.
--   - If songs.user_id is missing entirely, add it as TEXT.
--
-- Notes:
--   - Converting UUID -> TEXT preserves existing values (they become canonical uuid strings).
--   - If other tables reference songs.user_id via foreign keys, those must be updated separately.

DO $$
DECLARE
  user_id_type text;
  constraint_name text;
BEGIN
  IF to_regclass('public.songs') IS NULL THEN
    RETURN;
  END IF;

  SELECT c.data_type
    INTO user_id_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'songs'
    AND c.column_name = 'user_id';

  IF user_id_type IS NULL THEN
    ALTER TABLE public.songs ADD COLUMN user_id text;
    CREATE INDEX IF NOT EXISTS idx_songs_user_id ON public.songs (user_id);
    PERFORM pg_notify('pgrst', 'reload schema');
    RETURN;
  END IF;

  IF user_id_type = 'uuid' THEN
    -- Drop any FK constraints that use songs.user_id (best-effort).
    FOR constraint_name IN
      SELECT con.conname
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid = con.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
      JOIN pg_attribute att ON att.attrelid = rel.oid
      WHERE nsp.nspname = 'public'
        AND rel.relname = 'songs'
        AND con.contype = 'f'
        AND att.attname = 'user_id'
        AND att.attnum = ANY (con.conkey)
    LOOP
      BEGIN
        EXECUTE 'ALTER TABLE public.songs DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name);
      EXCEPTION WHEN others THEN
        -- ignore
        NULL;
      END;
    END LOOP;

    -- Drop any UUID default like gen_random_uuid()
    BEGIN
      EXECUTE 'ALTER TABLE public.songs ALTER COLUMN user_id DROP DEFAULT';
    EXCEPTION WHEN others THEN
      NULL;
    END;

    -- Convert UUID -> TEXT
    EXECUTE 'ALTER TABLE public.songs ALTER COLUMN user_id TYPE text USING user_id::text';

    -- Keep index around / recreate if missing
    CREATE INDEX IF NOT EXISTS idx_songs_user_id ON public.songs (user_id);
  END IF;

  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
