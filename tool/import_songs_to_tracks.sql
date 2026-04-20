-- Import all songs from 'songs' table into 'tracks' table
--
-- This will populate tracks with clean data including artwork URLs.
-- Run in Supabase SQL Editor.

begin;

-- First, clean up the messy test tracks (keep only the one test track)
delete from public.tracks 
where id != '1d925e97-d651-4465-94fc-705d87708a3d';

-- Insert all songs into tracks (avoiding duplicates)
insert into public.tracks (title, artist, audio_url, artwork_url, duration_ms)
select 
  s.title,
  'Unknown Artist' as artist,  -- songs table doesn't have artist name
  s.audio_url,
  s.thumbnail_url as artwork_url,
  s.duration as duration_ms  -- songs uses 'duration', tracks uses 'duration_ms'
from public.songs s
where not exists (
  select 1 from public.tracks t 
  where lower(trim(t.title)) = lower(trim(s.title))
)
and s.title is not null
and s.title != '';

-- Verify the import
select 
  count(*) as total_tracks,
  count(artwork_url) as tracks_with_artwork
from public.tracks;

-- Show sample
select id, title, artist, 
       left(coalesce(artwork_url, 'NULL'), 60) as artwork_preview
from public.tracks
order by created_at desc
limit 10;

commit;
