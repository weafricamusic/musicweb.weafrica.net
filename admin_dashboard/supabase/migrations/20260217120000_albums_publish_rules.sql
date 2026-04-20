-- Albums + publishing rules + song/video linkage.
--
-- Goals:
-- - Provide a canonical `public.albums` table.
-- - Link `songs` and `videos` to albums via `album_id`.
-- - Enforce consumer visibility via RLS (anon/authenticated can only SELECT published content).
--
-- Notes:
-- - Service role (used by admin/backend) bypasses RLS.
-- - This migration is designed to be idempotent across mixed legacy schemas.

create extension if not exists pgcrypto;

create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),

  -- Ownership (best-effort; different deployments use different identifiers).
  artist_id text,
  artist_firebase_uid text,

  title text not null,
  description text,
  cover_url text,

  -- Publishing controls
  visibility text not null default 'private' check (visibility in ('private','unlisted','public')),
  release_at timestamptz,
  published_at timestamptz,

  -- Monetization (best-effort; consumer app can interpret these).
  price_mwk integer not null default 0,
  price_coins integer not null default 0,

  is_active boolean not null default true,
  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table if exists public.albums
  add column if not exists artist_id text,
  add column if not exists artist_firebase_uid text,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists cover_url text,
  add column if not exists visibility text,
  add column if not exists release_at timestamptz,
  add column if not exists published_at timestamptz,
  add column if not exists price_mwk integer,
  add column if not exists price_coins integer,
  add column if not exists is_active boolean,
  add column if not exists meta jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- Defaults for legacy rows.
update public.albums set visibility = coalesce(visibility, 'private') where visibility is null;
update public.albums set price_mwk = coalesce(price_mwk, 0) where price_mwk is null;
update public.albums set price_coins = coalesce(price_coins, 0) where price_coins is null;
update public.albums set is_active = coalesce(is_active, true) where is_active is null;
update public.albums set meta = coalesce(meta, '{}'::jsonb) where meta is null;
update public.albums set created_at = coalesce(created_at, now()) where created_at is null;
update public.albums set updated_at = coalesce(updated_at, now()) where updated_at is null;

alter table public.albums alter column visibility set default 'private';
alter table public.albums alter column price_mwk set default 0;
alter table public.albums alter column price_coins set default 0;
alter table public.albums alter column is_active set default true;
alter table public.albums alter column meta set default '{}'::jsonb;
alter table public.albums alter column created_at set default now();
alter table public.albums alter column updated_at set default now();

-- Best-effort constraints.
do $$
begin
  begin
    alter table public.albums
      add constraint albums_visibility_check
      check (visibility in ('private','unlisted','public'));
  exception when duplicate_object then null;
  end;
end $$;

create index if not exists albums_artist_id_idx on public.albums (artist_id);
create index if not exists albums_artist_firebase_uid_idx on public.albums (artist_firebase_uid);
create index if not exists albums_visibility_idx on public.albums (visibility);
create index if not exists albums_release_at_idx on public.albums (release_at desc);
create index if not exists albums_published_at_idx on public.albums (published_at desc);
create index if not exists albums_is_active_idx on public.albums (is_active);

-- Link songs/videos to albums (if those tables exist).
alter table if exists public.songs add column if not exists album_id uuid;
alter table if exists public.videos add column if not exists album_id uuid;

create index if not exists songs_album_id_idx on public.songs (album_id);
create index if not exists videos_album_id_idx on public.videos (album_id);

-- Foreign keys are best-effort because some deployments have non-uuid song ids.
do $$
begin
  begin
    alter table public.songs
      add constraint songs_album_id_fkey
      foreign key (album_id) references public.albums(id)
      on delete set null;
  exception when undefined_table then null;
  exception when duplicate_object then null;
  exception when datatype_mismatch then null;
  exception when invalid_foreign_key then null;
  end;

  begin
    alter table public.videos
      add constraint videos_album_id_fkey
      foreign key (album_id) references public.albums(id)
      on delete set null;
  exception when undefined_table then null;
  exception when duplicate_object then null;
  exception when datatype_mismatch then null;
  exception when invalid_foreign_key then null;
  end;
end $$;

-- RLS: consumer can SELECT only published albums.
alter table public.albums enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'albums'
      and policyname = 'public albums only'
  ) then
    create policy "public albums only"
      on public.albums
      for select
      using (
        is_active = true
        and visibility = 'public'
        and (release_at is null or release_at <= now())
      );
  end if;
end $$;

-- Strengthen existing song/video consumer policies to respect album publish rules.
-- If a song/video is linked to an album, it is visible only if the album is visible.
-- Content without an album remains visible if is_active=true (preserves legacy behavior).
do $$
begin
  -- songs
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'songs'
      and policyname = 'public songs only'
  ) then
    execute $$alter policy "public songs only" on public.songs
      using (
        is_active = true
        and (
          album_id is null
          or exists (
            select 1
            from public.albums a
            where a.id = public.songs.album_id
              and a.is_active = true
              and a.visibility = 'public'
              and (a.release_at is null or a.release_at <= now())
          )
        )
      )$$;
  end if;

  -- videos
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'videos'
      and policyname = 'public videos only'
  ) then
    execute $$alter policy "public videos only" on public.videos
      using (
        is_active = true
        and (
          album_id is null
          or exists (
            select 1
            from public.albums a
            where a.id = public.videos.album_id
              and a.is_active = true
              and a.visibility = 'public'
              and (a.release_at is null or a.release_at <= now())
          )
        )
      )$$;
  end if;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
