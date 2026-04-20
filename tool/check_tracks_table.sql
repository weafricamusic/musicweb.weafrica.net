-- Check if 'tracks' table exists and what columns it has
--
-- Run in Supabase SQL Editor

-- 1) Does tracks table exist?
select table_name 
from information_schema.tables 
where table_schema = 'public' 
  and table_name in ('tracks', 'songs');

-- 2) What columns does tracks table have?
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' 
  and table_name = 'tracks'
order by ordinal_position;

-- 3) Sample data from tracks table (only using columns that exist)
select id, title, artist, created_at
from public.tracks
order by created_at desc
limit 5;

-- 4) Show ALL columns from first row to see what fields are available
select *
from public.tracks
limit 1;
