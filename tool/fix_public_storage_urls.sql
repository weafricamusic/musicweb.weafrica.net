-- Normalizes Supabase Storage URLs for PUBLIC buckets.
--
-- Your data contains a mix of URLs like:
--   .../storage/v1/object/songs/...
-- which should be:
--   .../storage/v1/object/public/songs/...
--
-- This script:
-- 1) Converts non-public object URLs to public object URLs (but leaves signed URLs alone).
-- 2) Standardizes thumbnail bucket naming to `song-thumbnails`.
-- 3) Optionally clears the legacy `thumbnail` placeholder.
--
-- Run in Supabase SQL Editor.

begin;

-- 0) Sanity preview (optional)
-- select id, audio_url, thumbnail_url, thumbnail from public.songs order by created_at desc limit 20;

-- 1) Ensure audio_url uses /public/ when it looks like a Storage URL and is NOT a signed URL.
update public.songs
set audio_url = replace(audio_url, '/storage/v1/object/', '/storage/v1/object/public/')
where audio_url is not null
  and audio_url like '%/storage/v1/object/%'
  and audio_url not like '%/storage/v1/object/public/%'
  and audio_url not like '%/storage/v1/object/sign/%';

-- 2) Ensure file_path uses /public/ if it is a Storage URL.
update public.songs
set file_path = replace(file_path, '/storage/v1/object/', '/storage/v1/object/public/')
where file_path is not null
  and file_path like '%/storage/v1/object/%'
  and file_path not like '%/storage/v1/object/public/%'
  and file_path not like '%/storage/v1/object/sign/%';

-- 3) Ensure thumbnail_url uses /public/ when it looks like a Storage URL and is NOT a signed URL.
update public.songs
set thumbnail_url = replace(thumbnail_url, '/storage/v1/object/', '/storage/v1/object/public/')
where thumbnail_url is not null
  and thumbnail_url like '%/storage/v1/object/%'
  and thumbnail_url not like '%/storage/v1/object/public/%'
  and thumbnail_url not like '%/storage/v1/object/sign/%';

-- 4) Standardize thumbnail bucket to `song-thumbnails` (hyphen) if some rows use underscore.
--    This only changes URLs that already target the public endpoint.
update public.songs
set thumbnail_url = replace(thumbnail_url, '/storage/v1/object/public/song_thumbnails/', '/storage/v1/object/public/song-thumbnails/')
where thumbnail_url is not null
  and thumbnail_url like '%/storage/v1/object/public/song_thumbnails/%';

-- 5) Optional: clear the legacy placeholder thumbnail field so it can't confuse downstream tools.
-- update public.songs
-- set thumbnail = null
-- where thumbnail is not null
--   and (
--     lower(thumbnail) = 'thumbnails/me.jpg'
--     or lower(thumbnail) like '%/thumbnails/me.jpg'
--     or lower(thumbnail) like '%/storage/v1/object/public/thumbnails/me.jpg%'
--     or lower(thumbnail) like '%/storage/v1/object/thumbnails/me.jpg%'
--   );

-- 6) Optional: set a default artwork URL if thumbnail_url is missing (edit the URL first).
-- update public.songs
-- set thumbnail_url = 'https://yourcdn.com/default-song-art.png'
-- where thumbnail_url is null or btrim(thumbnail_url) = '';

-- 7) Optional: Remove fake CDN placeholder URLs (yourcdn.com doesn't exist).
update public.songs
set thumbnail_url = null
where thumbnail_url is not null
  and lower(thumbnail_url) like '%yourcdn.com%';

-- 8) Optional: Verify no extremely short/invalid thumbnail_url values remain.
update public.songs
set thumbnail_url = null
where thumbnail_url is not null
  and (
    length(btrim(thumbnail_url)) < 10
    or lower(btrim(thumbnail_url)) = ''
    or lower(btrim(thumbnail_url)) = 'null'
    or lower(btrim(thumbnail_url)) = 'none'
  );

commit;

-- After running, spot-check:
-- select id, title, audio_url, thumbnail_url from public.songs where thumbnail_url is not null order by created_at desc limit 20;
-- select count(*) as total, count(thumbnail_url) as has_thumbnail from public.songs;
