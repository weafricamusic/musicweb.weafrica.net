-- Fix tracks table schema mismatch
-- The code uses 'tracks' table but database has 'songs'
-- Add missing language column and create tracks view

-- Add language column to songs table if it doesn't exist
alter table public.songs
  add column if not exists language text;

-- Drop existing tracks view if it exists
drop view if exists public.tracks;

-- Create tracks view that aliases songs table
-- This allows the code to use 'tracks' while the actual table is 'songs'
create view public.tracks as
select
  (to_jsonb(s)->>'id')::uuid as id,
  to_jsonb(s)->>'title' as title,
  to_jsonb(s)->>'artist' as artist,
  to_jsonb(s)->>'audio_url' as audio_url,
  to_jsonb(s)->>'artwork_url' as artwork_url,
  to_jsonb(s)->>'thumbnail_url' as thumbnail_url,
  to_jsonb(s)->>'image_url' as image_url,
  nullif(regexp_replace(to_jsonb(s)->>'duration_ms', '[^0-9]', '', 'g'), '')::bigint as duration_ms,
  to_jsonb(s)->>'genre' as genre,
  to_jsonb(s)->>'country' as country,
  to_jsonb(s)->>'language' as language,
  coalesce(to_jsonb(s)->>'album_name', to_jsonb(s)->>'album') as album,
  nullif(regexp_replace(to_jsonb(s)->>'year', '[^0-9]', '', 'g'), '')::int as year,
  nullif(regexp_replace(to_jsonb(s)->>'release_year', '[^0-9]', '', 'g'), '')::int as release_year,
  nullif(regexp_replace(to_jsonb(s)->>'releaseYear', '[^0-9]', '', 'g'), '')::int as "releaseYear",
  (to_jsonb(s)->>'created_at')::timestamptz as created_at,
  to_jsonb(s)->>'status' as status,
  nullif(regexp_replace(to_jsonb(s)->>'streams', '[^0-9]', '', 'g'), '')::int as streams,
  to_jsonb(s)->>'user_id' as user_id,
  to_jsonb(s)->>'firebase_uid' as firebase_uid
from public.songs s;

-- Grant permissions on the view
grant select, insert, update, delete on public.tracks to anon, authenticated;