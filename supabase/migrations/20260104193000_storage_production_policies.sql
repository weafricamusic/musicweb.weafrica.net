-- Production-safe Supabase Storage policies for WeAfrica Music
--
-- GOAL
-- - Anyone can READ (SELECT) public media thumbnails/videos.
-- - Only authenticated users can UPLOAD (INSERT).
-- - Only authenticated users can DELETE (DELETE).
--
-- NOTE
-- This will BREAK anonymous client-side uploads.
-- If your app uses Firebase Auth (no Supabase session), use Edge Functions to mint signed upload URLs.

DO $$
BEGIN
  -- video_thumbnails
  BEGIN
    DROP POLICY IF EXISTS "public upload video_thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "public delete video_thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "Authenticated upload video thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "Authenticated delete video thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  -- Public read (ensure exists, and uses TO public)
  BEGIN
    DROP POLICY IF EXISTS "Public read video thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  CREATE POLICY "Public read video thumbnails"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'video_thumbnails');

  CREATE POLICY "Authenticated upload video thumbnails"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'video_thumbnails');

  CREATE POLICY "Authenticated delete video thumbnails"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (bucket_id = 'video_thumbnails');

  -- videos
  BEGIN
    DROP POLICY IF EXISTS "public upload videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "public delete videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "Authenticated upload videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "Authenticated delete videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  BEGIN
    DROP POLICY IF EXISTS "Public read videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;

  CREATE POLICY "Public read videos"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'videos');

  CREATE POLICY "Authenticated upload videos"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'videos');

  CREATE POLICY "Authenticated delete videos"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (bucket_id = 'videos');
END $$;
