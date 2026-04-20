-- Diagnostic: Check current state of image URLs in database
--
-- Run this BEFORE running normalize_storage_urls.sql to see what needs fixing.
-- Run in Supabase SQL Editor.

-- 1) Show sample of current URLs
select 
  id,
  title,
  audio_url,
  thumbnail_url,
  created_at
from public.songs 
order by created_at desc 
limit 10;

-- 2) Count how many URLs are broken (missing /public/)
select 
  count(*) as total_songs,
  count(audio_url) as has_audio,
  count(thumbnail_url) as has_thumbnail,
  count(case when audio_url like '%/storage/v1/object/%' and audio_url not like '%/storage/v1/object/public/%' and audio_url not like '%/storage/v1/object/sign/%' then 1 end) as audio_missing_public,
  count(case when thumbnail_url like '%/storage/v1/object/%' and thumbnail_url not like '%/storage/v1/object/public/%' and thumbnail_url not like '%/storage/v1/object/sign/%' then 1 end) as thumb_missing_public,
  count(case when thumbnail_url like '%song_thumbnails%' then 1 end) as thumb_uses_underscore,
  count(case when thumbnail_url like '%song-thumbnails%' then 1 end) as thumb_uses_hyphen
from public.songs;

-- 3) Show examples of URLs that need fixing
select 
  'Missing /public/ in audio' as issue_type,
  audio_url as example_url
from public.songs
where audio_url like '%/storage/v1/object/%' 
  and audio_url not like '%/storage/v1/object/public/%'
  and audio_url not like '%/storage/v1/object/sign/%'
limit 3;

select 
  'Missing /public/ in thumbnail' as issue_type,
  thumbnail_url as example_url
from public.songs
where thumbnail_url like '%/storage/v1/object/%' 
  and thumbnail_url not like '%/storage/v1/object/public/%'
  and thumbnail_url not like '%/storage/v1/object/sign/%'
limit 3;

select 
  'Uses underscore bucket name' as issue_type,
  thumbnail_url as example_url
from public.songs
where thumbnail_url like '%song_thumbnails%'
limit 3;
