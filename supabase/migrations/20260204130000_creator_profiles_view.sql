-- Creator profiles (public directory)
-- Provides a unified read model for the consumer app by combining artists + djs.
-- NOTE: This is implemented as a VIEW so it stays in sync with the source tables.

create extension if not exists pgcrypto;
-- Ensure the columns referenced by the view exist (upgrade-safe).
alter table public.artists
  add column if not exists firebase_uid text,
  add column if not exists stage_name text,
  add column if not exists email text,
  add column if not exists bio text,
  add column if not exists profile_image text,
  add column if not exists status text,
  add column if not exists verified boolean,
  add column if not exists approved boolean,
  add column if not exists region text,
  add column if not exists created_at timestamptz;
alter table public.djs
  add column if not exists firebase_uid text,
  add column if not exists dj_name text,
  add column if not exists email text,
  add column if not exists profile_image text,
  add column if not exists status text,
  add column if not exists approved boolean,
  add column if not exists region text,
  add column if not exists created_at timestamptz;
-- Make approved predictable for RLS/view filters.
alter table public.artists alter column approved set default false;
alter table public.djs alter column approved set default false;
-- Create/replace view if no base table with that name exists.
do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'creator_profiles'
      and c.relkind = 'r'
  ) then
    -- A real table already exists; do not overwrite it.
    raise notice 'public.creator_profiles is a table; skipping view creation.';
  else
    execute $view$
      create or replace view public.creator_profiles as
      select
        a.id,
        coalesce(nullif(trim(a.firebase_uid), ''), nullif(trim(a.user_id::text), '')) as user_id,
        'artist'::text as role,
        coalesce(nullif(trim(a.stage_name), ''), nullif(trim(a.email), ''), a.id::text) as display_name,
        nullif(trim(a.profile_image), '') as avatar_url,
        nullif(trim(a.bio), '') as bio,
        a.region,
        a.status,
        a.verified,
        a.approved,
        a.created_at
      from public.artists a

      union all

      select
        d.id,
        coalesce(nullif(trim(d.firebase_uid), ''), nullif(trim(d.user_id::text), '')) as user_id,
        'dj'::text as role,
        coalesce(nullif(trim(d.dj_name), ''), nullif(trim(d.email), ''), d.id::text) as display_name,
        nullif(trim(d.profile_image), '') as avatar_url,
        null::text as bio,
        d.region,
        d.status,
        null::boolean as verified,
        d.approved,
        d.created_at
      from public.djs d;
    $view$;
  end if;
end $$;
-- Allow public reads (RLS on artists/djs still applies).
grant select on table public.creator_profiles to anon, authenticated;
-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';
