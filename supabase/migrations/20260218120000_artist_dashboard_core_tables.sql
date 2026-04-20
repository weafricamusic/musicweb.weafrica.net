-- Artist Dashboard core tables
-- Provides minimal, backend-backed support for:
-- - Boosts / promotions (per song/video)
-- - Artist inbox messages
-- - Play events for analytics charts
--
-- NOTE:
-- This uses MVP allow-all RLS policies (anon + authenticated).
-- Tighten policies for production.

create extension if not exists pgcrypto;

-- 1) Boosts
create table if not exists public.boosts (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artists(id) on delete set null,
  artist_uid text,
  song_id text,
  video_id text,
  coins_budget bigint not null default 0,
  country_target text,
  start_date date,
  end_date date,
  reach bigint not null default 0,
  status text not null default 'active' check (status in ('active','paused','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists boosts_artist_uid_created_at_idx on public.boosts (artist_uid, created_at desc);
create index if not exists boosts_artist_id_created_at_idx on public.boosts (artist_id, created_at desc);
create index if not exists boosts_song_id_idx on public.boosts (song_id);
create index if not exists boosts_video_id_idx on public.boosts (video_id);

alter table public.boosts enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'boosts'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy boosts_read_own on public.boosts for select to authenticated using (artist_uid = auth.uid()::text)';
  execute 'create policy boosts_insert_own on public.boosts for insert to authenticated with check (artist_uid = auth.uid()::text)';
  execute 'create policy boosts_update_own on public.boosts for update to authenticated using (artist_uid = auth.uid()::text) with check (artist_uid = auth.uid()::text)';
  execute 'create policy boosts_delete_own on public.boosts for delete to authenticated using (artist_uid = auth.uid()::text)';
end $$;

grant select, insert, update, delete on table public.boosts to authenticated;

-- 2) Messages (Artist Inbox)
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artists(id) on delete cascade,
  artist_uid text,
  sender_id text,
  sender_name text,
  message text,
  read boolean not null default false,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists messages_artist_uid_created_at_idx on public.messages (artist_uid, created_at desc);
create index if not exists messages_artist_id_created_at_idx on public.messages (artist_id, created_at desc);
create index if not exists messages_read_idx on public.messages (read, created_at desc);

alter table public.messages enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'messages'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy messages_read_own on public.messages for select to authenticated using (artist_uid = auth.uid()::text)';
  execute 'create policy messages_insert_own on public.messages for insert to authenticated with check (artist_uid = auth.uid()::text)';
  execute 'create policy messages_update_own on public.messages for update to authenticated using (artist_uid = auth.uid()::text) with check (artist_uid = auth.uid()::text)';
  execute 'create policy messages_delete_own on public.messages for delete to authenticated using (artist_uid = auth.uid()::text)';
end $$;

grant select, insert, update, delete on table public.messages to authenticated;

-- 3) Play events (Analytics)
create table if not exists public.play_events (
  id uuid primary key default gen_random_uuid(),
  content_type text not null default 'song' check (content_type in ('song','track','video')),
  content_id text not null,
  user_id text,
  created_at timestamptz not null default now()
);

create index if not exists play_events_content_created_at_idx on public.play_events (content_type, content_id, created_at desc);
create index if not exists play_events_created_at_idx on public.play_events (created_at desc);

alter table public.play_events enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'play_events'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy play_events_read_own on public.play_events for select to authenticated using (user_id = auth.uid()::text)';
  execute 'create policy play_events_insert_self on public.play_events for insert to authenticated with check (coalesce(user_id, auth.uid()::text) = auth.uid()::text)';
  execute 'create policy play_events_delete_own on public.play_events for delete to authenticated using (user_id = auth.uid()::text)';
end $$;

grant select, insert, delete on table public.play_events to authenticated;

-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
