-- Import audio files from Supabase Storage into public.tracks
--
-- This helps when you already uploaded songs/videos to Storage but the app shows nothing.
-- The app reads from public.tracks; Storage files must be referenced by rows.
--
-- HOW TO USE
-- 1) Replace <SUPABASE_URL> with your project URL (e.g. https://xxxx.supabase.co)
-- 2) (Optional) Adjust bucket names in the buckets array (default: songs + media)
-- 3) Run this in Supabase SQL Editor.
--
-- Notes:
-- - This imports common audio types only. Videos are not shown in the app yet.
-- - It uses storage.objects (Supabase-managed table).

-- Configure these two values:
--   <SUPABASE_URL>  e.g. https://abcd1234.supabase.co
--   buckets         e.g. ['songs','media']

with params as (
  select
    '<SUPABASE_URL>'::text as supabase_url,
    array['songs','media']::text[] as buckets
)

insert into public.tracks (title, artist, audio_url, created_at)
select
  -- Title: filename without folders and without extension
  nullif(
    trim(
      regexp_replace(
        regexp_replace(name, '^.*/', ''),
        '\\.[^.]+$',
        ''
      )
    ),
    ''
  ),
  -- Artist: unknown (update later)
  'Unknown Artist',
  -- Public URL (requires bucket/object to be public)
  concat(params.supabase_url, '/storage/v1/object/public/', bucket_id, '/', name),
  now()
from storage.objects
cross join params
where bucket_id = any(params.buckets)
  and (
    lower(name) like '%.mp3'
    or lower(name) like '%.m4a'
    or lower(name) like '%.aac'
    or lower(name) like '%.wav'
    or lower(name) like '%.ogg'
    or lower(name) like '%.flac'
  )
  and not exists (
    select 1
    from public.tracks t
    where t.audio_url = concat(params.supabase_url, '/storage/v1/object/public/', bucket_id, '/', name)
  );

-- Verify:
-- select count(*) from public.tracks;
-- select title, audio_url from public.tracks order by created_at desc limit 20;
