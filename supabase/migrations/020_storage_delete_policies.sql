-- Allow client-side deletes in Supabase Storage for MVP/testing.
-- NOT production-safe: allows public deletes for selected buckets.

DO $$
BEGIN
  -- songs
  BEGIN
    DROP POLICY IF EXISTS "public delete songs" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;
  CREATE POLICY "public delete songs"
    ON storage.objects FOR DELETE
    USING (bucket_id = 'songs');

  -- song_thumbnails
  BEGIN
    DROP POLICY IF EXISTS "public delete song_thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;
  CREATE POLICY "public delete song_thumbnails"
    ON storage.objects FOR DELETE
    USING (bucket_id = 'song_thumbnails');

  -- videos
  BEGIN
    DROP POLICY IF EXISTS "public delete videos" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;
  CREATE POLICY "public delete videos"
    ON storage.objects FOR DELETE
    USING (bucket_id = 'videos');

  -- video_thumbnails
  BEGIN
    DROP POLICY IF EXISTS "public delete video_thumbnails" ON storage.objects;
  EXCEPTION WHEN undefined_object THEN
    -- ignore
  END;
  CREATE POLICY "public delete video_thumbnails"
    ON storage.objects FOR DELETE
    USING (bucket_id = 'video_thumbnails');
END $$;
