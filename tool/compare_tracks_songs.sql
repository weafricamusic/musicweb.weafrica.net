-- Diagnostic: Why songs and tracks don't match
--
-- Run in Supabase SQL Editor to see what's in each table

-- 1) What's in tracks?
select 'TRACKS' as table_name, count(*) as count from public.tracks
union all
select 'SONGS' as table_name, count(*) from public.songs;

-- 2) Sample titles from each table
(select 'TRACKS' as source, title from public.tracks limit 5)
union all
(select 'SONGS' as source, title from public.songs limit 5);

-- 3) Check if any titles match (case-insensitive)
select 
  t.title as track_title,
  s.title as song_title,
  s.thumbnail_url
from public.tracks t
join public.songs s on lower(trim(t.title)) = lower(trim(s.title))
limit 10;

-- 4) If no matches, you need to either:
--    a) Insert tracks from songs, or
--    b) Insert songs from tracks, or
--    c) Manually add artwork_url to tracks
