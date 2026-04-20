-- Delete specific artists in LOCAL/DEV only.
--
-- This script is safety-first:
--  1) It selects and prints matches first.
--  2) It deletes related rows in known tables when present.
--  3) It ends with ROLLBACK by default so you can review output.
--
-- After confirming the matches are correct, replace the final `ROLLBACK;`
-- with `COMMIT;` and rerun.

begin;

-- Names/usernames you requested to delete (case-insensitive match across common name fields).
with wanted(q) as (
  select unnest(array[
    'steve msungama',
    'joel jere',
    'bandasiimon098',
    'mike phiri',
    'banda simon',
    'jojo',
    'admin'
  ])
),
normalized as (
  select distinct lower(trim(q)) as q
  from wanted
  where q is not null and trim(q) <> ''
),
matches as (
  select
    a.id,
    a.user_id,
    a.username,
    a.name,
    a.artist_name,
    a.stage_name,
    a.display_name,
    a.full_name,
    a.title,
    a.artist,
    a.stage,
    a.email,
    a.created_at,
    a.updated_at
  from public.artists a
  join normalized n on (
    lower(trim(coalesce(a.username, ''))) = n.q
    or lower(trim(coalesce(a.display_name, ''))) = n.q
    or lower(trim(coalesce(a.stage_name, ''))) = n.q
    or lower(trim(coalesce(a.artist_name, ''))) = n.q
    or lower(trim(coalesce(a.name, ''))) = n.q
    or lower(trim(coalesce(a.full_name, ''))) = n.q
    or lower(trim(coalesce(a.title, ''))) = n.q
    or lower(trim(coalesce(a.artist, ''))) = n.q
    or lower(trim(coalesce(a.stage, ''))) = n.q
  )
)
select *
from matches
order by coalesce(username, display_name, stage_name, artist_name, name, full_name, user_id, email);

-- Perform deletes in a DO block so we can conditionally touch dependent tables.
do $$
declare
  artist_ids uuid[];
  artist_user_ids text[];
  deleted_wallets bigint := 0;
  deleted_songs bigint := 0;
  deleted_artists bigint := 0;
begin
  select
    coalesce(array_agg(m.id), '{}'::uuid[]),
    coalesce(array_agg(m.user_id), '{}'::text[])
  into artist_ids, artist_user_ids
  from (
    with wanted(q) as (
      select unnest(array[
        'steve msungama',
        'joel jere',
        'bandasiimon098',
        'mike phiri',
        'banda simon',
        'jojo',
        'admin'
      ])
    ),
    normalized as (
      select distinct lower(trim(q)) as q
      from wanted
      where q is not null and trim(q) <> ''
    )
    select a.id, a.user_id
    from public.artists a
    join normalized n on (
      lower(trim(coalesce(a.username, ''))) = n.q
      or lower(trim(coalesce(a.display_name, ''))) = n.q
      or lower(trim(coalesce(a.stage_name, ''))) = n.q
      or lower(trim(coalesce(a.artist_name, ''))) = n.q
      or lower(trim(coalesce(a.name, ''))) = n.q
      or lower(trim(coalesce(a.full_name, ''))) = n.q
      or lower(trim(coalesce(a.title, ''))) = n.q
      or lower(trim(coalesce(a.artist, ''))) = n.q
      or lower(trim(coalesce(a.stage, ''))) = n.q
    )
  ) m;

  if array_length(artist_ids, 1) is null then
    raise notice 'No matching artists found; nothing deleted.';
    return;
  end if;

  -- Dependent table: artist_wallets (artist_id is TEXT and typically equals artists.user_id)
  if to_regclass('public.artist_wallets') is not null then
    execute 'delete from public.artist_wallets where artist_id = any ($1)'
      using artist_user_ids;
    get diagnostics deleted_wallets = row_count;
  end if;

  -- Dependent table: songs (artist_id is UUID and may reference artists.id)
  if to_regclass('public.songs') is not null then
    begin
      execute 'delete from public.songs where artist_id = any ($1)'
        using artist_ids;
      get diagnostics deleted_songs = row_count;
    exception
      when undefined_column then
        -- Some environments use a different schema for songs.
        deleted_songs := 0;
    end;
  end if;

  delete from public.artists where id = any (artist_ids);
  get diagnostics deleted_artists = row_count;

  raise notice 'Deleted: artists=%, artist_wallets=%, songs=%', deleted_artists, deleted_wallets, deleted_songs;
end $$;

-- Safety default: keep rollback until you confirm the SELECT output above is correct.
rollback;
-- commit;
