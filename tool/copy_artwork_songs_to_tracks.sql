-- Copy artwork URLs from 'songs' table to 'tracks' table
--
-- This matches songs by title only (songs table may not have artist column).
-- Run in Supabase SQL Editor.

begin;

-- Update tracks with artwork from songs, matching by title
update public.tracks t
set artwork_url = s.thumbnail_url
from public.songs s
where lower(trim(t.title)) = lower(trim(s.title))
  and s.thumbnail_url is not null
  and (t.artwork_url is null or t.artwork_url = '');

-- Show what was updated
select 
  t.id,
  t.title,
  t.artist,
  t.artwork_url
from public.tracks t
where t.artwork_url is not null
order by t.created_at desc
limit 20;

commit;

-- Verify counts:
-- select count(*) as total, count(artwork_url) as has_artwork from public.tracks;
