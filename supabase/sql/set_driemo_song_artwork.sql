-- Sets artwork/thumbnail/image fields for all Driemo songs.
-- Safe to re-run (idempotent) and works across schema variants.

DO $$
DECLARE
  desired_url text := 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/album-covers/songs/driemo.jpg';
  has_updated_at boolean := false;
  col record;
  updated_count bigint;
BEGIN
  -- Detect optional columns.
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name = 'updated_at'
  ) INTO has_updated_at;

  FOR col IN (
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name IN ('artwork_url', 'thumbnail_url', 'image_url', 'cover_url')
    ORDER BY column_name
  ) LOOP
    IF has_updated_at THEN
      EXECUTE format(
        'UPDATE public.songs '
        'SET %I = $1, updated_at = now() '
        'WHERE ( '
        '  lower(COALESCE(artist, '''')) = lower(''Driemo'') '
        '  OR audio_url ILIKE ''%%/Driemo-%%'' '
        '  OR audio_url ILIKE ''%%Driemo%%'' '
        ') '
        'AND (%I IS DISTINCT FROM $1)',
        col.column_name,
        col.column_name
      ) USING desired_url;
    ELSE
      EXECUTE format(
        'UPDATE public.songs '
        'SET %I = $1 '
        'WHERE ( '
        '  lower(COALESCE(artist, '''')) = lower(''Driemo'') '
        '  OR audio_url ILIKE ''%%/Driemo-%%'' '
        '  OR audio_url ILIKE ''%%Driemo%%'' '
        ') '
        'AND (%I IS DISTINCT FROM $1)',
        col.column_name,
        col.column_name
      ) USING desired_url;
    END IF;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE 'Updated %.% for Driemo songs: % rows', 'songs', col.column_name, updated_count;
  END LOOP;

  -- Quick sanity check.
  RAISE NOTICE 'Sample rows:';
  PERFORM 1;
END $$;

-- View a quick sample (run manually after the DO block if you want output in SQL editor):
-- SELECT id, title, artist, artwork_url, thumbnail_url, image_url, cover_url, audio_url
-- FROM public.songs
-- WHERE lower(COALESCE(artist,'')) = lower('Driemo') OR audio_url ILIKE '%Driemo%'
-- ORDER BY created_at DESC NULLS LAST
-- LIMIT 25;
