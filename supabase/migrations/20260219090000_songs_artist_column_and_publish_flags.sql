-- Ensure songs schema supports app/Edge Function publishing.
-- Fixes PostgREST errors like:
--   "Could not find the 'artist' column of 'songs' in the schema cache"
--
-- This migration is idempotent and safe to apply multiple times.

DO $$
DECLARE
  relkind_char "char";
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  -- Detect whether public.songs exists and what it is.
  SELECT c.relkind
  INTO relkind_char
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'songs'
  LIMIT 1;

  -- Create table if it doesn't exist (some environments were created manually).
  IF relkind_char IS NULL THEN
    CREATE TABLE public.songs (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      title text,
      artist text,
      artist_id uuid,
      genre text,
      country text,
      language text,
      audio_url text NOT NULL,
      artwork_url text,
      user_id text,
      album_id uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz,
      -- Publish/visibility flags (optional; app/backends will adapt if missing)
      is_public boolean,
      is_active boolean,
      approved boolean,
      is_published boolean,
      -- Soft-delete style status (aligned with 20260111193100_final_schema_alignment.sql)
      status text NOT NULL DEFAULT 'active',
      streams integer NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_songs_created_at ON public.songs (created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_songs_user_id ON public.songs (user_id);
    CREATE INDEX IF NOT EXISTS idx_songs_artist_id ON public.songs (artist_id);
  ELSIF relkind_char <> 'r' THEN
    -- If songs exists as a VIEW (or other non-table), we cannot ALTER TABLE.
    RAISE NOTICE 'public.songs exists as relkind=% (not a table). This migration only applies to TABLEs. Convert/dropped-and-recreate as a TABLE if you need to INSERT into songs and add columns like artist.', relkind_char;
    -- Still ask PostgREST to reload schema cache in case a manual fix was applied.
    PERFORM pg_notify('pgrst', 'reload schema');
    RETURN;
  END IF;

  -- Add missing columns for existing tables.
  ALTER TABLE public.songs
    ADD COLUMN IF NOT EXISTS title text,
    ADD COLUMN IF NOT EXISTS artist text,
    ADD COLUMN IF NOT EXISTS artist_id uuid,
    ADD COLUMN IF NOT EXISTS genre text,
    ADD COLUMN IF NOT EXISTS country text,
    ADD COLUMN IF NOT EXISTS language text,
    ADD COLUMN IF NOT EXISTS audio_url text,
    ADD COLUMN IF NOT EXISTS artwork_url text,
    ADD COLUMN IF NOT EXISTS user_id text,
    ADD COLUMN IF NOT EXISTS album_id uuid,
    ADD COLUMN IF NOT EXISTS created_at timestamptz,
    ADD COLUMN IF NOT EXISTS updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS is_public boolean,
    ADD COLUMN IF NOT EXISTS is_active boolean,
    ADD COLUMN IF NOT EXISTS approved boolean,
    ADD COLUMN IF NOT EXISTS is_published boolean,
    ADD COLUMN IF NOT EXISTS status text,
    ADD COLUMN IF NOT EXISTS streams integer;

  -- Best-effort defaults (guarded).
  BEGIN
    ALTER TABLE public.songs ALTER COLUMN created_at SET DEFAULT now();
  EXCEPTION WHEN undefined_column THEN NULL;
  END;

  BEGIN
    ALTER TABLE public.songs ALTER COLUMN status SET DEFAULT 'active';
  EXCEPTION WHEN undefined_column THEN NULL;
  END;

  BEGIN
    ALTER TABLE public.songs ALTER COLUMN streams SET DEFAULT 0;
  EXCEPTION WHEN undefined_column THEN NULL;
  END;

  -- Helpful indexes.
  CREATE INDEX IF NOT EXISTS idx_songs_user_id ON public.songs (user_id);
  CREATE INDEX IF NOT EXISTS idx_songs_artist_id ON public.songs (artist_id);
  CREATE INDEX IF NOT EXISTS idx_songs_album_id ON public.songs (album_id);

  -- FK (best-effort): songs.artist_id -> artists.id
  IF to_regclass('public.artists') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'songs_artist_id_fkey'
    ) THEN
      BEGIN
        ALTER TABLE public.songs
          ADD CONSTRAINT songs_artist_id_fkey
          FOREIGN KEY (artist_id)
          REFERENCES public.artists(id)
          ON DELETE SET NULL;
      EXCEPTION
        WHEN duplicate_object THEN NULL;
        WHEN undefined_table THEN NULL;
        WHEN undefined_column THEN NULL;
        WHEN datatype_mismatch THEN NULL;
      END;
    END IF;
  END IF;

  -- Refresh PostgREST schema cache.
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
