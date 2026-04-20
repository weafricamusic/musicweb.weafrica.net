-- Update existing public.songs rows to point at the correct MP3 URLs for the album "The Magician".
--
-- This script is intentionally conservative:
-- - It resolves the album via public.albums.title (so you don't need the UUID)
-- - Each UPDATE targets at most 1 row (LIMIT 1)
-- - It only updates when the URL is different (IS DISTINCT FROM)
--
-- Before running:
-- 1) Ensure there is exactly one album row titled "The Magician".
-- 2) Ensure songs for that album already exist (this is UPDATE-only).

-- 0) Sanity check: album must exist.
SELECT id, title
FROM public.albums
WHERE lower(title) = lower('The Magician');

-- 0a) Publish album so it shows up in the app
UPDATE public.albums
SET is_published = true,
    visibility = 'public',
    is_active = true,
    published_at = COALESCE(published_at, now()),
    updated_at = now()
WHERE id = (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
AND (
  is_published IS DISTINCT FROM true
  OR visibility IS DISTINCT FROM 'public'
  OR is_active IS DISTINCT FROM true
  OR published_at IS NULL
);

-- 0a2) Ensure songs are linked to this album (and insert missing rows)
WITH album AS (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
UPDATE public.songs s
SET album_id = (SELECT id FROM album),
    updated_at = now()
WHERE s.audio_url ILIKE '%/media/songs/the-magician/%'
  AND s.album_id IS DISTINCT FROM (SELECT id FROM album);

-- Some environments have a legacy NOT NULL column: public.songs.file_path
-- (typically a storage object key like `songs/the-magician/<file>.mp3`).
-- This block inserts the missing songs and populates file_path if required.
DO $$
DECLARE
  album_uuid uuid;
  has_file_path boolean;
BEGIN
  SELECT id
  INTO album_uuid
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1;

  IF album_uuid IS NULL THEN
    RAISE EXCEPTION 'Album not found: The Magician';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name = 'file_path'
  )
  INTO has_file_path;

  -- Backfill file_path for already-present rows (best-effort).
  IF has_file_path THEN
    EXECUTE $$
      UPDATE public.songs
      SET file_path = regexp_replace(audio_url, '^https?://[^/]+/storage/v1/object/public/media/', ''),
          updated_at = now()
      WHERE album_id = $1
        AND file_path IS NULL
        AND audio_url ILIKE '%/storage/v1/object/public/media/%';
    $$ USING album_uuid;
  END IF;

  IF has_file_path THEN
    EXECUTE $$
      WITH desired(track_no, title, audio_url) AS (
        VALUES
          (1, 'Every Moment', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/01.Driemo-Every-Moment.mp3'),
          (2, 'Away (feat. Malinga x Bee Jay)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/02.Driemo-Away-ft-Malinga-x-Bee-Jay.mp3'),
          (3, 'Ndani (feat. Suffix)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/03.Driemo-Ndani-ft-Suffix.mp3'),
          (4, 'Mantha', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/04.Driemo-Mantha.mp3'),
          (6, 'Poko (feat. Kae Chaps)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/06.Driemo-Poko-ft-Kae-Chaps.mp3'),
          (7, 'Spiderman', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/07.Driemo-Spiderman.mp3'),
          (8, 'Mukapepese', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/08.Driemo-Mukapepese.mp3'),
          (9, 'Nawe', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/09.Driemo-Nawe.mp3'),
          (10, 'Ninvela So (feat. Yo Maps)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/10.Driemo-Ninvela-So-ft-Yo-Maps.mp3'),
          (11, 'Conditionally', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/11.Driemo-Conditionally.mp3'),
          (12, 'Joker', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/12.Driemo-Joker.mp3'),
          (13, 'Nobody Cares', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/13.Driemo-Nobody-Cares.mp3'),
          (15, 'Definition of Love', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/15.Driemo-Definition-of-Love.mp3'),
          (16, 'Just Like That / Danger', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/16.Driemo-Just-Like-ThatDanger.mp3'),
          (18, 'All of Me (feat. Loiso)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/18.Driemo-All-of-Me-ft-Loiso.mp3'),
          (19, 'Tsamba', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/19.Driemo-Tsamba.mp3'),
          (20, 'Amake Imulati', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/20.Driemo-Amake-Imulati.mp3'),
          (21, 'Pensulo', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/Driemo-Pensulo%20(1).mp3')
      )
      INSERT INTO public.songs (
        title,
        artist,
        genre,
        audio_url,
        file_path,
        album_id,
        approved,
        is_active,
        created_at,
        updated_at
      )
      SELECT
        d.title,
        'Driemo' AS artist,
        'R&B' AS genre,
        d.audio_url,
        regexp_replace(d.audio_url, '^https?://[^/]+/storage/v1/object/public/media/', '') AS file_path,
        $1 AS album_id,
        true AS approved,
        true AS is_active,
        now() AS created_at,
        now() AS updated_at
      FROM desired d
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.songs s
        WHERE s.album_id = $1
          AND (
            s.audio_url = d.audio_url
            OR lower(COALESCE(s.title, '')) = lower(d.title)
          )
      );
    $$ USING album_uuid;
  ELSE
    EXECUTE $$
      WITH desired(track_no, title, audio_url) AS (
        VALUES
          (1, 'Every Moment', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/01.Driemo-Every-Moment.mp3'),
          (2, 'Away (feat. Malinga x Bee Jay)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/02.Driemo-Away-ft-Malinga-x-Bee-Jay.mp3'),
          (3, 'Ndani (feat. Suffix)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/03.Driemo-Ndani-ft-Suffix.mp3'),
          (4, 'Mantha', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/04.Driemo-Mantha.mp3'),
          (6, 'Poko (feat. Kae Chaps)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/06.Driemo-Poko-ft-Kae-Chaps.mp3'),
          (7, 'Spiderman', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/07.Driemo-Spiderman.mp3'),
          (8, 'Mukapepese', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/08.Driemo-Mukapepese.mp3'),
          (9, 'Nawe', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/09.Driemo-Nawe.mp3'),
          (10, 'Ninvela So (feat. Yo Maps)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/10.Driemo-Ninvela-So-ft-Yo-Maps.mp3'),
          (11, 'Conditionally', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/11.Driemo-Conditionally.mp3'),
          (12, 'Joker', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/12.Driemo-Joker.mp3'),
          (13, 'Nobody Cares', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/13.Driemo-Nobody-Cares.mp3'),
          (15, 'Definition of Love', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/15.Driemo-Definition-of-Love.mp3'),
          (16, 'Just Like That / Danger', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/16.Driemo-Just-Like-ThatDanger.mp3'),
          (18, 'All of Me (feat. Loiso)', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/18.Driemo-All-of-Me-ft-Loiso.mp3'),
          (19, 'Tsamba', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/19.Driemo-Tsamba.mp3'),
          (20, 'Amake Imulati', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/20.Driemo-Amake-Imulati.mp3'),
          (21, 'Pensulo', 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/Driemo-Pensulo%20(1).mp3')
      )
      INSERT INTO public.songs (
        title,
        artist,
        genre,
        audio_url,
        album_id,
        approved,
        is_active,
        created_at,
        updated_at
      )
      SELECT
        d.title,
        'Driemo' AS artist,
        'R&B' AS genre,
        d.audio_url,
        $1 AS album_id,
        true AS approved,
        true AS is_active,
        now() AS created_at,
        now() AS updated_at
      FROM desired d
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.songs s
        WHERE s.album_id = $1
          AND (
            s.audio_url = d.audio_url
            OR lower(COALESCE(s.title, '')) = lower(d.title)
          )
      );
    $$ USING album_uuid;
  END IF;
END $$;

-- 0b) Set album cover
UPDATE public.albums
SET cover_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/album-covers/songs/driemo.jpg',
    updated_at = now()
WHERE id = (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
AND cover_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/album-covers/songs/driemo.jpg';

-- 0bb) Set Driemo song artwork (fills whichever columns exist in your schema).
DO $$
DECLARE
  desired_url text := 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/album-covers/songs/driemo.jpg';
  has_updated_at boolean := false;
  col record;
BEGIN
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
  END LOOP;
END $$;

-- 0c) Set genre for all songs in this album
UPDATE public.songs
SET genre = 'R&B',
    updated_at = now()
WHERE album_id = (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
AND genre IS DISTINCT FROM 'R&B';

-- 0d) Mark songs as approved + active so RLS allows playback/listing
UPDATE public.songs
SET approved = true,
    is_active = true,
    updated_at = now()
WHERE album_id = (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
AND (
  approved IS DISTINCT FROM true
  OR is_active IS DISTINCT FROM true
);

-- 0e) Best-effort extra flags (ignore if your schema doesn't have these columns)
DO $$
BEGIN
  BEGIN
    UPDATE public.songs
    SET is_public = true,
        updated_at = now()
    WHERE album_id = (
      SELECT id
      FROM public.albums
      WHERE lower(title) = lower('The Magician')
      ORDER BY created_at NULLS LAST, id
      LIMIT 1
    )
    AND is_public IS DISTINCT FROM true;
  EXCEPTION WHEN undefined_column THEN
    NULL;
  END;

  BEGIN
    UPDATE public.songs
    SET is_published = true,
        updated_at = now()
    WHERE album_id = (
      SELECT id
      FROM public.albums
      WHERE lower(title) = lower('The Magician')
      ORDER BY created_at NULLS LAST, id
      LIMIT 1
    )
    AND is_published IS DISTINCT FROM true;
  EXCEPTION WHEN undefined_column THEN
    NULL;
  END;
END $$;

-- 1) Preview matches (adjust title patterns if any return 0 or > 1).
WITH album AS (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
SELECT
  s.id,
  s.title,
  s.audio_url
FROM public.songs s
WHERE s.album_id = (SELECT id FROM album)
  AND (
    s.title ILIKE '%Every%Moment%'
    OR s.title ILIKE '%Away%Malinga%Bee%Jay%'
    OR s.title ILIKE '%Ndani%Suffix%'
    OR s.title ILIKE '%Mantha%'
    OR s.title ILIKE '%Poko%Kae%Chaps%'
    OR s.title ILIKE '%Spiderman%'
    OR s.title ILIKE '%Mukapepese%'
    OR s.title ILIKE '%Nawe%'
    OR s.title ILIKE '%Ninvela%So%Yo%Maps%'
    OR s.title ILIKE '%Conditionally%'
    OR s.title ILIKE '%Joker%'
    OR s.title ILIKE '%Nobody%Cares%'
    OR s.title ILIKE '%Definition%Love%'
    OR s.title ILIKE '%Just%Like%That%'
    OR s.title ILIKE '%Danger%'
    OR s.title ILIKE '%All%of%Me%'
    OR s.title ILIKE '%Loiso%'
    OR s.title ILIKE '%Tsamba%'
    OR s.title ILIKE '%Amake%Imulati%'
    OR s.title ILIKE '%Pensulo%'
  )
ORDER BY s.title;

-- 2) Apply updates.
-- NOTE: If a track doesn't update (0 rows), tweak the ILIKE pattern to match your stored title.

-- 01. Every Moment
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/01.Driemo-Every-Moment.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Every%Moment%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/01.Driemo-Every-Moment.mp3';

-- 02. Away (ft Malinga x Bee Jay)
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/02.Driemo-Away-ft-Malinga-x-Bee-Jay.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Away%Malinga%Bee%Jay%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/02.Driemo-Away-ft-Malinga-x-Bee-Jay.mp3';

-- 03. Ndani (ft Suffix)
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/03.Driemo-Ndani-ft-Suffix.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Ndani%Suffix%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/03.Driemo-Ndani-ft-Suffix.mp3';

-- 04. Mantha
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/04.Driemo-Mantha.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Mantha%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/04.Driemo-Mantha.mp3';

-- 06. Poko (ft Kae Chaps)
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/06.Driemo-Poko-ft-Kae-Chaps.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Poko%Kae%Chaps%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/06.Driemo-Poko-ft-Kae-Chaps.mp3';

-- 07. Spiderman
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/07.Driemo-Spiderman.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Spiderman%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/07.Driemo-Spiderman.mp3';

-- 08. Mukapepese
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/08.Driemo-Mukapepese.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Mukapepese%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/08.Driemo-Mukapepese.mp3';

-- 09. Nawe
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/09.Driemo-Nawe.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Nawe%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/09.Driemo-Nawe.mp3';

-- 10. Ninvela So (ft Yo Maps)
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/10.Driemo-Ninvela-So-ft-Yo-Maps.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Ninvela%So%Yo%Maps%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/10.Driemo-Ninvela-So-ft-Yo-Maps.mp3';

-- 11. Conditionally
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/11.Driemo-Conditionally.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Conditionally%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/11.Driemo-Conditionally.mp3';

-- 12. Joker
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/12.Driemo-Joker.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Joker%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/12.Driemo-Joker.mp3';

-- 13. Nobody Cares
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/13.Driemo-Nobody-Cares.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Nobody%Cares%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/13.Driemo-Nobody-Cares.mp3';

-- 15. Definition of Love
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/15.Driemo-Definition-of-Love.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Definition%Love%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/15.Driemo-Definition-of-Love.mp3';

-- 16. Just Like That / Danger
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/16.Driemo-Just-Like-ThatDanger.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND (s.title ILIKE '%Just%Like%That%' OR s.title ILIKE '%Danger%')
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/16.Driemo-Just-Like-ThatDanger.mp3';

-- 18. All of Me (ft Loiso)
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/18.Driemo-All-of-Me-ft-Loiso.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND (s.title ILIKE '%All%of%Me%' OR s.title ILIKE '%Loiso%')
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/18.Driemo-All-of-Me-ft-Loiso.mp3';

-- 19. Tsamba
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/19.Driemo-Tsamba.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Tsamba%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/19.Driemo-Tsamba.mp3';

-- 20. Amake Imulati
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/20.Driemo-Amake-Imulati.mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Amake%Imulati%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/20.Driemo-Amake-Imulati.mp3';

-- Pensulo (filename includes " (1)")
UPDATE public.songs
SET audio_url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/Driemo-Pensulo%20(1).mp3',
    updated_at = now()
WHERE id = (
  SELECT s.id
  FROM public.songs s
  WHERE s.album_id = (
    SELECT id FROM public.albums WHERE lower(title) = lower('The Magician') ORDER BY created_at NULLS LAST, id LIMIT 1
  )
    AND s.title ILIKE '%Pensulo%'
  ORDER BY s.created_at NULLS LAST, s.id
  LIMIT 1
)
AND audio_url IS DISTINCT FROM 'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/songs/the-magician/Driemo-Pensulo%20(1).mp3';

-- 3) Post-check: list updated URLs for this album.
WITH album AS (
  SELECT id
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
SELECT s.title, s.audio_url, s.updated_at
FROM public.songs s
WHERE s.album_id = (SELECT id FROM album)
  AND s.audio_url ILIKE '%/media/songs/the-magician/%'
ORDER BY s.title;

-- 4) Post-check: confirm flags match app expectations
WITH album AS (
  SELECT *
  FROM public.albums
  WHERE lower(title) = lower('The Magician')
  ORDER BY created_at NULLS LAST, id
  LIMIT 1
)
SELECT
  a.id as album_id,
  a.title,
  a.is_published,
  a.visibility,
  a.is_active,
  a.published_at,
  a.cover_url,
  (
    SELECT count(*)::int
    FROM public.songs s
    WHERE s.album_id = a.id
  ) as songs_total,
  (
    SELECT count(*)::int
    FROM public.songs s
    WHERE s.album_id = a.id
      AND s.approved = true
      AND s.is_active = true
      AND COALESCE(nullif(trim(s.audio_url), ''), NULL) IS NOT NULL
  ) as songs_playable_under_rls
FROM album a;
