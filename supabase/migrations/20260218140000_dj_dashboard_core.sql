-- DJ Dashboard core schema
-- Provides backend-backed tables for:
-- - DJ profile editing
-- - DJ sets/mixes
-- - DJ playlists + tracks
-- - DJ scheduling (writes to dj_events)
-- - DJ boosts + inbox support (extends existing boosts/messages)
-- - Storage bucket for DJ set audio
--
-- SECURITY NOTE: This uses MVP allow-all RLS policies for new tables.

create extension if not exists pgcrypto;

-- 1) DJ profile (editable by the app; keyed by Firebase UID)
create table if not exists public.dj_profile (
  id uuid primary key default gen_random_uuid(),
  dj_uid text not null,
  stage_name text,
  country text,
  bio text,
  profile_photo text,
  followers_count bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (dj_uid)
);

create index if not exists dj_profile_dj_uid_idx on public.dj_profile (dj_uid);

alter table public.dj_profile enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'dj_profile'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy dj_profile_read_public on public.dj_profile for select to anon, authenticated using (true)';
  execute 'create policy dj_profile_insert_own on public.dj_profile for insert to authenticated with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_profile_update_own on public.dj_profile for update to authenticated using (auth.uid()::text = dj_uid) with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_profile_delete_own on public.dj_profile for delete to authenticated using (auth.uid()::text = dj_uid)';
end $$;

grant select on table public.dj_profile to anon, authenticated;
grant insert, update, delete on table public.dj_profile to authenticated;

-- 2) DJ sets / mixes
create table if not exists public.dj_sets (
  id uuid primary key default gen_random_uuid(),
  dj_uid text not null,
  title text not null,
  genre text,
  duration integer,
  audio_url text not null,
  plays bigint not null default 0,
  likes bigint not null default 0,
  comments bigint not null default 0,
  coins_earned bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_sets_dj_uid_created_at_idx on public.dj_sets (dj_uid, created_at desc);

alter table public.dj_sets enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'dj_sets'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy dj_sets_read_public on public.dj_sets for select to anon, authenticated using (true)';
  execute 'create policy dj_sets_insert_own on public.dj_sets for insert to authenticated with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_sets_update_own on public.dj_sets for update to authenticated using (auth.uid()::text = dj_uid) with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_sets_delete_own on public.dj_sets for delete to authenticated using (auth.uid()::text = dj_uid)';
end $$;

grant select on table public.dj_sets to anon, authenticated;
grant insert, update, delete on table public.dj_sets to authenticated;

-- 3) DJ playlists
create table if not exists public.dj_playlists (
  id uuid primary key default gen_random_uuid(),
  dj_uid text not null,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_playlists_dj_uid_created_at_idx on public.dj_playlists (dj_uid, created_at desc);

alter table public.dj_playlists enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'dj_playlists'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy dj_playlists_read_public on public.dj_playlists for select to anon, authenticated using (true)';
  execute 'create policy dj_playlists_insert_own on public.dj_playlists for insert to authenticated with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_playlists_update_own on public.dj_playlists for update to authenticated using (auth.uid()::text = dj_uid) with check (auth.uid()::text = dj_uid)';
  execute 'create policy dj_playlists_delete_own on public.dj_playlists for delete to authenticated using (auth.uid()::text = dj_uid)';
end $$;

grant select on table public.dj_playlists to anon, authenticated;
grant insert, update, delete on table public.dj_playlists to authenticated;

create table if not exists public.dj_playlist_tracks (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.dj_playlists(id) on delete cascade,
  song_id text not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (playlist_id, song_id)
);

create index if not exists dj_playlist_tracks_playlist_pos_idx on public.dj_playlist_tracks (playlist_id, position asc);

alter table public.dj_playlist_tracks enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'dj_playlist_tracks'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy dj_playlist_tracks_read_public on public.dj_playlist_tracks for select to anon, authenticated using (true)';
  execute '
    create policy dj_playlist_tracks_insert_own
    on public.dj_playlist_tracks
    for insert
    to authenticated
    with check (
      exists (
        select 1
        from public.dj_playlists p
        where p.id = playlist_id
          and p.dj_uid = auth.uid()::text
      )
    )
  ';
  execute '
    create policy dj_playlist_tracks_update_own
    on public.dj_playlist_tracks
    for update
    to authenticated
    using (
      exists (
        select 1
        from public.dj_playlists p
        where p.id = playlist_id
          and p.dj_uid = auth.uid()::text
      )
    )
    with check (
      exists (
        select 1
        from public.dj_playlists p
        where p.id = playlist_id
          and p.dj_uid = auth.uid()::text
      )
    )
  ';
  execute '
    create policy dj_playlist_tracks_delete_own
    on public.dj_playlist_tracks
    for delete
    to authenticated
    using (
      exists (
        select 1
        from public.dj_playlists p
        where p.id = playlist_id
          and p.dj_uid = auth.uid()::text
      )
    )
  ';
end $$;

grant select on table public.dj_playlist_tracks to anon, authenticated;
grant insert, update, delete on table public.dj_playlist_tracks to authenticated;

-- 4) Allow DJ scheduling writes using dj_events (table exists but was read-only).
-- Keep it MVP-open (aligns with other dashboard tables).

do $$
begin
  if to_regclass('public.dj_events') is not null then
    alter table public.dj_events enable row level security;

    -- Add idempotent write policies
    begin
      create policy "DJ events insert own" on public.dj_events
        for insert to authenticated
        with check (auth.uid()::text = dj_id::text);
    exception when duplicate_object then null;
    end;

    begin
      create policy "DJ events update own" on public.dj_events
        for update to authenticated
        using (auth.uid()::text = dj_id::text)
        with check (auth.uid()::text = dj_id::text);
    exception when duplicate_object then null;
    end;

    begin
      create policy "DJ events delete own" on public.dj_events
        for delete to authenticated
        using (auth.uid()::text = dj_id::text);
    exception when duplicate_object then null;
    end;

    grant select on table public.dj_events to anon, authenticated;
    grant insert, update, delete on table public.dj_events to authenticated;
  end if;
end $$;

-- 5) Extend boosts + messages tables to support DJs too.

-- boosts additions
alter table public.boosts
  add column if not exists dj_uid text,
  add column if not exists content_id text,
  add column if not exists content_type text;

create index if not exists boosts_dj_uid_created_at_idx on public.boosts (dj_uid, created_at desc);
create index if not exists boosts_content_idx on public.boosts (content_type, content_id);

-- messages additions
alter table public.messages
  add column if not exists dj_uid text;

create index if not exists messages_dj_uid_created_at_idx on public.messages (dj_uid, created_at desc);

-- 6) Views to match requested backend names (read model).
-- dj_live_sessions mapped to dj_events where event_type='live'.

do $$
begin
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='dj_live_sessions' and c.relkind='r'
  ) then
    -- Table exists; do not overwrite.
    null;
  else
    execute $v$
      create or replace view public.dj_live_sessions as
      select
        e.id,
        e.dj_id as dj_id,
        e.starts_at as start_time,
        e.ends_at as end_time,
        coalesce((e.metadata->>'coins_earned')::numeric, 0)::numeric as coins_earned,
        coalesce((e.metadata->>'viewers')::int, 0) as viewers
      from public.dj_events e
      where lower(coalesce(e.event_type,'')) in ('live','dj_live');
    $v$;
    grant select on table public.dj_live_sessions to anon, authenticated;
  end if;
end $$;

-- dj_battles mapped to battles

do $$
begin
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='dj_battles' and c.relkind='r'
  ) then
    null;
  else
    execute $v$
      create or replace view public.dj_battles as
      select
        b.id,
        nullif((b.participant_ids[1])::text,'') as dj1_id,
        nullif((b.participant_ids[2])::text,'') as dj2_id,
        b.winner_id,
        b.prize_pool as coins_earned
      from public.battles b;
    $v$;
    grant select on table public.dj_battles to anon, authenticated;
  end if;
end $$;

-- 7) Storage bucket for DJ sets audio
do $$
begin
  insert into storage.buckets (id, name, public)
  values ('dj-sets', 'dj-sets', true)
  on conflict (id) do update set public = excluded.public;
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  execute 'alter table storage.objects enable row level security';
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  -- Read
  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects' and policyname='public read dj-sets'
  ) then
    execute 'create policy "public read dj-sets" on storage.objects for select using (bucket_id = ''dj-sets'')';
  end if;

  -- Upload
  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects' and policyname='public upload dj-sets'
  ) then
    execute 'create policy "public upload dj-sets" on storage.objects for insert with check (bucket_id = ''dj-sets'')';
  end if;
exception
  when insufficient_privilege then
    null;
end $$;

-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';
