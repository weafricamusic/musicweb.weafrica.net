-- Albums publishing + connect songs to albums
-- - Adds songs.album_id FK -> albums(id)
-- - Adds albums.is_published flag (consumer visibility gate)
--
-- Idempotent + safe for existing environments.

DO $$
BEGIN
  IF to_regclass('public.albums') IS NOT NULL THEN
    ALTER TABLE public.albums
      ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT false;

    -- Optional compatibility columns commonly used by the app/backend.
    ALTER TABLE public.albums
      ADD COLUMN IF NOT EXISTS visibility text,
      ADD COLUMN IF NOT EXISTS is_active boolean,
      ADD COLUMN IF NOT EXISTS published_at timestamptz,
      ADD COLUMN IF NOT EXISTS release_at timestamptz,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz,
      ADD COLUMN IF NOT EXISTS user_id text;

    -- Best-effort defaults
    BEGIN
      ALTER TABLE public.albums ALTER COLUMN visibility SET DEFAULT 'private';
    EXCEPTION WHEN undefined_column THEN NULL;
    END;

    BEGIN
      ALTER TABLE public.albums ALTER COLUMN is_active SET DEFAULT true;
    EXCEPTION WHEN undefined_column THEN NULL;
    END;

    CREATE INDEX IF NOT EXISTS idx_albums_is_published ON public.albums (is_published);
    CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON public.albums (artist_id);
  END IF;

  IF to_regclass('public.songs') IS NOT NULL AND to_regclass('public.albums') IS NOT NULL THEN
    -- Add album_id if missing
    ALTER TABLE public.songs
      ADD COLUMN IF NOT EXISTS album_id uuid;

    -- Add FK (guarded; IF NOT EXISTS not supported for constraints)
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'songs_album_id_fkey'
    ) THEN
      BEGIN
        ALTER TABLE public.songs
          ADD CONSTRAINT songs_album_id_fkey
          FOREIGN KEY (album_id)
          REFERENCES public.albums(id)
          ON DELETE SET NULL;
      EXCEPTION
        WHEN duplicate_object THEN NULL;
        WHEN undefined_table THEN NULL;
      END;
    END IF;

    CREATE INDEX IF NOT EXISTS idx_songs_album_id ON public.songs (album_id);
  END IF;

  -- Refresh PostgREST schema cache.
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
