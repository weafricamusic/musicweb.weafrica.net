-- Better diagnostic: What's REALLY broken?
--
-- Run this to understand the actual state of your database.

-- 1) Sample recent songs with their URLs
select 
  id,
  title,
  left(audio_url, 80) as audio_url_preview,
  left(thumbnail_url, 80) as thumbnail_url_preview
from public.songs 
where created_at > now() - interval '30 days'
order by created_at desc 
limit 15;

-- 2) Count different URL patterns
select 
  'Total songs' as metric,
  count(*) as count
from public.songs
union all
select 'Has audio_url', count(*) from public.songs where audio_url is not null
union all
select 'Has thumbnail_url', count(*) from public.songs where thumbnail_url is not null
union all
select 'Audio missing /public/', count(*) from public.songs 
where audio_url like '%/storage/v1/object/%' 
  and audio_url not like '%/storage/v1/object/public/%'
  and audio_url not like '%/storage/v1/object/sign/%'
union all
select 'Thumbnail missing /public/', count(*) from public.songs 
where thumbnail_url like '%/storage/v1/object/%' 
  and thumbnail_url not like '%/storage/v1/object/public/%'
  and thumbnail_url not like '%/storage/v1/object/sign/%'
union all
select 'Thumbnail uses underscore (song_thumbnails)', count(*) from public.songs 
where thumbnail_url like '%/storage/v1/object/%song_thumbnails%'
union all
select 'Thumbnail uses hyphen (song-thumbnails)', count(*) from public.songs 
where thumbnail_url like '%/storage/v1/object/%song-thumbnails%'
union all
select 'Audio uses underscore (songs_/...)', count(*) from public.songs 
where audio_url like '%/storage/v1/object/%songs_%'
union all
select 'External URLs (non-supabase)', count(*) from public.songs 
where audio_url is not null and audio_url not like '%supabase.co%' and audio_url not like '%/storage/%';

-- 3) Show exact examples of broken patterns
select 
  'audio URL uses underscore bucket' as issue,
  audio_url as example
from public.songs 
where audio_url like '%/storage/v1/object/public/songs_%'
limit 2;

select 
  'thumbnail missing public' as issue,
  thumbnail_url as example
from public.songs 
where thumbnail_url like '%/storage/v1/object/%' 
  and thumbnail_url not like '%/storage/v1/object/public/%'
  and thumbnail_url not like '%/storage/v1/object/sign/%'
limit 2;

-- 4) What buckets do the URLs reference?
select 
  case 
    when thumbnail_url like '%/storage/v1/object/public/%' then
      substring(thumbnail_url from 'storage/v1/object/public/([a-z0-9_-]+)/')
    else
      substring(thumbnail_url from 'storage/v1/object/([a-z0-9_-]+)/')
  end as referenced_bucket,
  count(*) as count
from public.songs
where thumbnail_url is not null
  and thumbnail_url like '%/storage/v1/object/%'
group by referenced_bucket
order by count desc;

-- 5) Show actual thumbnail URLs to verify bucket existence
select 
  thumbnail_url
from public.songs
where thumbnail_url is not null
  and thumbnail_url like '%/storage/v1/object/%'
order by created_at desc
limit 5;
