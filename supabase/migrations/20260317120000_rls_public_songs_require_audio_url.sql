-- Require a usable audio_url for consumer visibility.
--
-- Extends the existing RLS rule (approved + active) so anon/authenticated
-- clients cannot read rows that would be unplayable in the app.
--
-- Notes:
-- - This does NOT change the creator/admin ability to manage their own songs.
-- - A non-empty audio_url does not guarantee the file exists; the app still
--   has player-level skip/retry protection.

DO $$
BEGIN
  IF to_regclass('public.songs') IS NULL THEN
    RAISE NOTICE 'public.songs not found; skipping RLS update.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS "Public read approved active songs" ON public.songs;

  CREATE POLICY "Public read approved active songs"
  ON public.songs
  FOR SELECT
  TO anon, authenticated
  USING (
    approved = true
    AND is_active = true
    AND audio_url IS NOT NULL
    AND length(trim(audio_url)) > 0
  );
END $$;
