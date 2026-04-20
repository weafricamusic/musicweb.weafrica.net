-- Normalizes Supabase Storage URLs for PUBLIC buckets (TRACKS table).
--
-- Your app reads from 'tracks' table, not 'songs'.
-- This script fixes artwork_url in the tracks table.
--
-- Run in Supabase SQL Editor.

begin;

-- 0) Preview current state
-- select id, title, audio_url, artwork_url from public.tracks order by created_at desc limit 10;

-- 1) Ensure audio_url uses /public/ when it looks like a Storage URL and is NOT a signed URL.
update public.tracks
set audio_url = replace(audio_url, '/storage/v1/object/', '/storage/v1/object/public/')
where audio_url is not null
  and audio_url like '%/storage/v1/object/%'
  and audio_url not like '%/storage/v1/object/public/%'
  and audio_url not like '%/storage/v1/object/sign/%';

-- 2) Ensure artwork_url uses /public/ when it looks like a Storage URL and is NOT a signed URL.
update public.tracks
set artwork_url = replace(artwork_url, '/storage/v1/object/', '/storage/v1/object/public/')
where artwork_url is not null
  and artwork_url like '%/storage/v1/object/%'
  and artwork_url not like '%/storage/v1/object/public/%'
  and artwork_url not like '%/storage/v1/object/sign/%';

-- 3) Standardize bucket to `song-thumbnails` (hyphen) if some rows use underscore.
update public.tracks
set artwork_url = replace(artwork_url, '/storage/v1/object/public/song_thumbnails/', '/storage/v1/object/public/song-thumbnails/')
where artwork_url is not null
  and artwork_url like '%/storage/v1/object/public/song_thumbnails/%';

-- 4) Remove invalid/placeholder URLs
update public.tracks
set artwork_url = null
where artwork_url is not null
  and (
    lower(artwork_url) like '%yourcdn.com%'
    or length(btrim(artwork_url)) < 10
    or lower(btrim(artwork_url)) in ('', 'null', 'none')
  );

commit;

-- After running, verify:
-- select id, title, artwork_url from public.tracks where artwork_url is not null order by created_at desc limit 10;
-- select count(*) as total, count(artwork_url) as has_artwork from public.tracks;
