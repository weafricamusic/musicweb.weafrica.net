-- Cleanup Featured Artists: keep ONLY artist1
--
-- WHAT THIS DOES
-- - Deletes all rows from public.featured_artists except the one for artist1
-- - Ensures artist1 is present in public.featured_artists (upsert)
--
-- WARNING
-- This is a DESTRUCTIVE operation for the featured list.
-- Run this only if you're sure you want to remove other featured artists.
--
-- HOW TO RUN
-- - Supabase Dashboard -> SQL Editor -> paste & run
-- - Or locally via psql against your Supabase DB
--
-- If your artist1 account uses a different name/email, edit the matcher below.

-- 0) Sanity checks (won't modify data)
select
  'featured_artists exists' as check,
  to_regclass('public.featured_artists') as value;

select
  'artists exists' as check,
  to_regclass('public.artists') as value;

-- 1) Inspect candidate artist1 rows
-- (If this returns multiple rows, the script will pick the oldest created_at.)
select
  id,
  stage_name,
  display_name,
  username,
  email,
  created_at
from public.artists
where
  lower(trim(coalesce(stage_name, ''))) = 'artist1'
  or lower(trim(coalesce(display_name, ''))) = 'artist1'
  or lower(trim(coalesce(username, ''))) = 'artist1'
  or lower(trim(coalesce(artist_name, ''))) = 'artist1'
  or lower(trim(coalesce(name, ''))) = 'artist1'
  or lower(trim(coalesce(email, ''))) = 'artist1@weafrica.test'
order by created_at asc nulls last;

-- 2) Apply cleanup + upsert
do $$
declare
  v_artist1_id uuid;
begin
  if to_regclass('public.featured_artists') is null then
    raise exception 'public.featured_artists does not exist. Apply migration supabase/migrations/20260202120000_featured_artists.sql first.';
  end if;

  if to_regclass('public.artists') is null then
    raise exception 'public.artists does not exist. Apply your artists table migration first (e.g. supabase/migrations/008_create_artists.sql).';
  end if;

  select a.id
    into v_artist1_id
  from public.artists a
  where
    lower(trim(coalesce(a.stage_name, ''))) = 'artist1'
    or lower(trim(coalesce(a.display_name, ''))) = 'artist1'
    or lower(trim(coalesce(a.username, ''))) = 'artist1'
    or lower(trim(coalesce(a.artist_name, ''))) = 'artist1'
    or lower(trim(coalesce(a.name, ''))) = 'artist1'
    or lower(trim(coalesce(a.email, ''))) = 'artist1@weafrica.test'
  order by a.created_at asc nulls last
  limit 1;

  if v_artist1_id is null then
    raise exception 'Could not find artist1 in public.artists. Update the matcher (stage_name/display_name/username/email) and re-run.';
  end if;

  -- Delete every featured artist entry except artist1.
  delete from public.featured_artists
  where artist_id <> v_artist1_id;

  -- Ensure artist1 is featured (idempotent).
  insert into public.featured_artists (artist_id, priority, is_active)
  values (v_artist1_id, 1000, true)
  on conflict (artist_id) do update
    set priority = excluded.priority,
        is_active = excluded.is_active;

  raise notice 'Done. Kept artist_id=% in public.featured_artists', v_artist1_id;
end $$;

-- 3) Verify result
select
  fa.id as featured_id,
  fa.artist_id,
  fa.country_code,
  fa.priority,
  fa.is_active,
  fa.created_at,
  a.stage_name,
  a.display_name,
  a.username,
  a.email
from public.featured_artists fa
join public.artists a on a.id = fa.artist_id
order by fa.priority desc, fa.created_at desc;
