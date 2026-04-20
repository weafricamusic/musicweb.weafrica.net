-- Add artist_id to play_events so Artist Dashboard analytics can query by artist.
-- Safe/idempotent.

DO $$
BEGIN
  IF to_regclass('public.play_events') IS NOT NULL THEN
    ALTER TABLE public.play_events
      ADD COLUMN IF NOT EXISTS artist_id uuid;

    CREATE INDEX IF NOT EXISTS play_events_artist_created_at_idx
      ON public.play_events (artist_id, created_at DESC);

    -- Refresh PostgREST schema cache.
    PERFORM pg_notify('pgrst', 'reload schema');
  END IF;
END $$;
