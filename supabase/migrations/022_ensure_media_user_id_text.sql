-- Ensure media tables have a Firebase-UID-compatible owner column.
-- Some Flutter code inserts/filters on `user_id`; older schemas may not have it.
-- This migration is idempotent.

DO $$
BEGIN
  IF to_regclass('public.songs') IS NOT NULL THEN
    ALTER TABLE public.songs
      ADD COLUMN IF NOT EXISTS user_id text;

    CREATE INDEX IF NOT EXISTS idx_songs_user_id ON public.songs (user_id);
  END IF;

  IF to_regclass('public.videos') IS NOT NULL THEN
    ALTER TABLE public.videos
      ADD COLUMN IF NOT EXISTS user_id text;

    CREATE INDEX IF NOT EXISTS idx_videos_user_id ON public.videos (user_id);
  END IF;

  -- Ask PostgREST to reload schema cache.
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
