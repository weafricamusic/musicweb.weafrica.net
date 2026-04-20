-- Ensure creator_profiles view never emits rows with null/blank user_id.
-- Applies only when public.creator_profiles is a view.

do $$
declare
  rel_kind "char";
begin
  select c.relkind
    into rel_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'creator_profiles';

  if rel_kind = 'v' then
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
      where coalesce(nullif(trim(a.firebase_uid), ''), nullif(trim(a.user_id::text), '')) is not null

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
      from public.djs d
      where coalesce(nullif(trim(d.firebase_uid), ''), nullif(trim(d.user_id::text), '')) is not null;
    $view$;

    grant select on table public.creator_profiles to anon, authenticated;
  else
    raise notice 'public.creator_profiles is not a view (relkind=%). Skipping view filter migration.', coalesce(rel_kind::text, 'missing');
  end if;
end $$;

notify pgrst, 'reload schema';
