-- Fix consumer Library data issues:
-- 1) Albums not showing (missing/null album metadata)
-- 2) Artists showing UUIDs instead of readable names
--
-- Safe to run multiple times.

begin;

-- ------------------------------------------------------------
-- A) Ensure tracks.album exists
-- ------------------------------------------------------------
alter table if exists public.tracks
  add column if not exists album text;

-- ------------------------------------------------------------
-- B) Backfill tracks.album from legacy columns (if they exist)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.tracks') is null then
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tracks' and column_name='album_title'
  ) then
    execute $sql$
      update public.tracks
      set album = nullif(trim(album_title), '')
      where coalesce(trim(album), '') = ''
        and coalesce(trim(album_title), '') <> ''
    $sql$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tracks' and column_name='album_name'
  ) then
    execute $sql$
      update public.tracks
      set album = nullif(trim(album_name), '')
      where coalesce(trim(album), '') = ''
        and coalesce(trim(album_name), '') <> ''
    $sql$;
  end if;
end $$;

-- ------------------------------------------------------------
-- C) Backfill tracks.album from songs table (title match)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.tracks') is null or to_regclass('public.songs') is null then
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='songs' and column_name='album'
  ) then
    execute $sql$
      update public.tracks t
      set album = nullif(trim(s.album), '')
      from public.songs s
      where coalesce(trim(t.album), '') = ''
        and lower(trim(s.title)) = lower(trim(t.title))
        and coalesce(trim(s.album), '') <> ''
    $sql$;
  end if;
end $$;

-- ------------------------------------------------------------
-- D) Replace UUID-like tracks.artist with artist names from artists table
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.tracks') is null or to_regclass('public.artists') is null then
    return;
  end if;

  -- If tracks.artist_id exists, prefer that join path.
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tracks' and column_name='artist_id'
  ) then
    execute $sql$
      update public.tracks t
      set artist = coalesce(
        nullif(trim(a.display_name), ''),
        nullif(trim(a.stage_name), ''),
        nullif(trim(a.artist_name), ''),
        nullif(trim(a.name), ''),
        nullif(trim(a.full_name), ''),
        nullif(trim(a.username), ''),
        nullif(trim(a.title), ''),
        nullif(trim(a.artist), ''),
        nullif(trim(a.email), ''),
        t.artist
      )
      from public.artists a
      where (
          coalesce(trim(t.artist), '') = ''
          or trim(t.artist) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        )
        and (
          t.artist_id::text = a.id::text
          or t.artist_id::text = a.user_id
          or t.artist_id::text = a.firebase_uid
        )
    $sql$;
  end if;

  -- Also handle rows where tracks.artist itself is an artists.id UUID.
  execute $sql$
    update public.tracks t
    set artist = coalesce(
      nullif(trim(a.display_name), ''),
      nullif(trim(a.stage_name), ''),
      nullif(trim(a.artist_name), ''),
      nullif(trim(a.name), ''),
      nullif(trim(a.full_name), ''),
      nullif(trim(a.username), ''),
      nullif(trim(a.title), ''),
      nullif(trim(a.artist), ''),
      nullif(trim(a.email), ''),
      t.artist
    )
    from public.artists a
    where trim(t.artist) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and (
        lower(trim(t.artist)) = lower(a.id::text)
        or lower(trim(t.artist)) = lower(coalesce(a.user_id, ''))
        or lower(trim(t.artist)) = lower(coalesce(a.firebase_uid, ''))
      )
  $sql$;
end $$;

-- ------------------------------------------------------------
-- E) If creator_profiles is a TABLE (not VIEW), repair UUID display_name
-- ------------------------------------------------------------
do $$
declare
  rel_kind "char";
begin
  select c.relkind
  into rel_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'creator_profiles'
  limit 1;

  if rel_kind = 'r' then
    -- Artist names from artists table
    if to_regclass('public.artists') is not null then
      execute $sql$
        update public.creator_profiles cp
        set display_name = coalesce(
          nullif(trim(a.display_name), ''),
          nullif(trim(a.stage_name), ''),
          nullif(trim(a.artist_name), ''),
          nullif(trim(a.name), ''),
          nullif(trim(a.full_name), ''),
          nullif(trim(a.username), ''),
          nullif(trim(a.email), ''),
          cp.display_name
        )
        from public.artists a
        where cp.role = 'artist'
          and cp.display_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          and (
            cp.id::text = a.id::text
            or cp.user_id = a.user_id
            or cp.user_id = a.firebase_uid
          )
      $sql$;
    end if;

    -- DJ names from djs table
    if to_regclass('public.djs') is not null then
      execute $sql$
        update public.creator_profiles cp
        set display_name = coalesce(
          nullif(trim(d.dj_name), ''),
          nullif(trim(d.email), ''),
          cp.display_name
        )
        from public.djs d
        where cp.role = 'dj'
          and cp.display_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          and (
            cp.id::text = d.id::text
            or cp.user_id = d.user_id::text
            or cp.user_id = d.firebase_uid
          )
      $sql$;
    end if;
  end if;
end $$;

commit;

-- Quick checks
-- select title, artist, album from public.tracks order by created_at desc limit 30;
-- select role, display_name from public.creator_profiles order by created_at desc limit 50;
