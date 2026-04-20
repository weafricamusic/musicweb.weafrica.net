-- Import video files from Supabase Storage into public.videos
--
-- This helps when you already uploaded videos to Storage but the app shows nothing.
-- The app reads from public.videos; Storage files must be referenced by rows.
--
-- HOW TO USE
-- 1) Replace <SUPABASE_URL> with your project URL (e.g. https://xxxx.supabase.co)
-- 2) Replace <BUCKET> with your video bucket name (e.g. videos)
-- 3) Run this in Supabase SQL Editor.
--
-- Notes:
-- - It imports common video types only.
-- - It uses storage.objects (Supabase-managed table).
-- - If your bucket is private, this public URL won’t work; you’d need signed URLs.

insert into public.videos (title, video_url, created_at)
select
  regexp_replace(name, '^.*/', ''),
  concat('<SUPABASE_URL>', '/storage/v1/object/public/', bucket_id, '/', name),
  now()
from storage.objects
where bucket_id = '<BUCKET>'
  and (
    lower(name) like '%.mp4'
    or lower(name) like '%.mov'
    or lower(name) like '%.m4v'
    or lower(name) like '%.webm'
    or lower(name) like '%.mkv'
  )
  and not exists (
    select 1
    from public.videos v
    where v.video_url = concat('<SUPABASE_URL>', '/storage/v1/object/public/', bucket_id, '/', name)
  );

-- Verify:
-- select count(*) from public.videos;
-- select title, video_url from public.videos order by created_at desc limit 20;
