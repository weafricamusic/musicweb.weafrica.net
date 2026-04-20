-- Seed data for WeAfrique Music
-- Run this in Supabase SQL Editor after tool/supabase_schema.sql

-- 1) Quick sanity check: insert a public MP3 so the app shows something immediately.
insert into public.tracks (title, artist, audio_url)
values (
  'Test Track',
  'WeAfrique',
  'https://storage.googleapis.com/exoplayer-test-media-0/play.mp3'
);

-- 2) Template for Supabase Storage PUBLIC bucket URLs:
-- audio_url format:
--   https://<PROJECT_REF>.supabase.co/storage/v1/object/public/<BUCKET>/<PATH>
-- Example:
-- insert into public.tracks (title, artist, audio_url, artwork_url)
-- values (
--   'My Song',
--   'My Artist',
--   'https://<PROJECT_REF>.supabase.co/storage/v1/object/public/songs/afrobeats/my_song.mp3',
--   'https://<PROJECT_REF>.supabase.co/storage/v1/object/public/artwork/my_song.jpg'
-- );

-- 3) Verify:
-- select id, title, artist, audio_url, created_at from public.tracks order by created_at desc limit 20;
