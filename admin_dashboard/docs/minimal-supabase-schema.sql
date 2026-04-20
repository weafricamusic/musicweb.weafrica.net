-- Minimal Supabase schema for WeAfrique Music
-- Apply in Supabase SQL editor (Database -> SQL).
-- This file is safe to commit (no secrets).
--
-- Note: This repo already contains additional production migrations in supabase/migrations/.
-- If you run this against an existing WeAfrique DB, review for naming collisions first.

-- Needed for gen_random_uuid()
create extension if not exists pgcrypto;

-- Legacy compatibility: some older PayChangu flows recorded duration in
-- public.paychangu_payments.months. Keep this schema upgrade-safe.
alter table if exists public.paychangu_payments add column if not exists months integer;
alter table if exists public.paychangu_payments add column if not exists tx_ref text;
alter table if exists public.paychangu_payments add column if not exists uid text;
alter table if exists public.paychangu_payments add column if not exists raw jsonb;
alter table if exists public.paychangu_payments add column if not exists meta jsonb;

-- Hint PostgREST to refresh its schema cache quickly.
notify pgrst, 'reload schema';

-- SUBSCRIPTIONS (plans + user subscription state)
-- These tables are queried by:
-- - GET /api/subscriptions/me
-- - GET /api/subscriptions/plans
-- and are typically accessed server-side with the Supabase service-role key.
create table if not exists public.subscription_plans (
  plan_id text primary key,

  -- Optional grouping for admin/consumer filtering
  audience text,

  name text not null,
  price_mwk integer not null default 0 check (price_mwk >= 0),
  currency text not null default 'MWK',
  billing_interval text not null default 'month' check (billing_interval in ('month','week')),
  is_active boolean not null default true,

  -- Core entitlements
  coins_multiplier integer not null default 1 check (coins_multiplier >= 1),
  ads_enabled boolean not null default true,
  can_participate_battles boolean not null default false,
  battle_priority text not null default 'none' check (battle_priority in ('none','standard','priority')),
  analytics_level text not null default 'basic' check (analytics_level in ('basic','standard','advanced')),

  -- Content access
  content_access text not null default 'limited' check (content_access in ('limited','standard','exclusive')),
  content_limit_ratio numeric(4,3) check (content_limit_ratio is null or (content_limit_ratio >= 0 and content_limit_ratio <= 1)),

  -- Premium perks
  featured_status boolean not null default false,
  perks jsonb not null default '{}'::jsonb,
  features jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint subscription_plans_audience_check
    check (audience is null or audience in ('consumer','artist','dj'))
);

create index if not exists subscription_plans_price_idx on public.subscription_plans (price_mwk);
create index if not exists subscription_plans_audience_idx on public.subscription_plans (audience);

alter table public.subscription_plans enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_plans'
      and policyname = 'deny_all_subscription_plans'
  ) then
    create policy deny_all_subscription_plans
      on public.subscription_plans
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Seed consumer plans (idempotent). Keep JSON fields minimal; the app merges DB perks with built-in defaults.
insert into public.subscription_plans (
  audience,
  plan_id,
  name,
  price_mwk,
  currency,
  billing_interval,
  coins_multiplier,
  ads_enabled,
  can_participate_battles,
  battle_priority,
  analytics_level,
  content_access,
  content_limit_ratio,
  featured_status,
  perks,
  features,
  is_active
)
values
  ('consumer','free','Free',0,'MWK','month',1,true,false,'none','basic','limited',0.300,false,'{}'::jsonb,'{}'::jsonb,true),
  ('consumer','premium','Premium',5000,'MWK','month',2,false,true,'standard','standard','standard',null,false,'{}'::jsonb,'{}'::jsonb,true),
  ('consumer','premium_weekly','Premium (Weekly)',1250,'MWK','week',2,false,true,'standard','standard','standard',null,false,'{}'::jsonb,'{}'::jsonb,true),
  ('consumer','platinum','Platinum',8500,'MWK','month',3,false,true,'priority','advanced','exclusive',null,true,'{}'::jsonb,'{}'::jsonb,true),
  ('consumer','platinum_weekly','Platinum (Weekly)',2125,'MWK','week',3,false,true,'priority','advanced','exclusive',null,true,'{}'::jsonb,'{}'::jsonb,true)
on conflict (plan_id) do update set
  audience = excluded.audience,
  name = excluded.name,
  price_mwk = excluded.price_mwk,
  currency = excluded.currency,
  billing_interval = excluded.billing_interval,
  coins_multiplier = excluded.coins_multiplier,
  ads_enabled = excluded.ads_enabled,
  can_participate_battles = excluded.can_participate_battles,
  battle_priority = excluded.battle_priority,
  analytics_level = excluded.analytics_level,
  content_access = excluded.content_access,
  content_limit_ratio = excluded.content_limit_ratio,
  featured_status = excluded.featured_status,
  perks = excluded.perks,
  features = excluded.features,
  is_active = excluded.is_active,
  updated_at = now();

create table if not exists public.user_subscriptions (
  id bigserial primary key,
  user_id text not null,
  plan_id text not null references public.subscription_plans (plan_id),
  status text not null default 'active' check (status in ('active','canceled','cancelled','expired','replaced')),
  started_at timestamptz not null default now(),
  ends_at timestamptz,
  auto_renew boolean not null default true,
  country_code text not null default 'MW',
  source text,

  -- Optional fields used by some admin/dashboard migrations
  subscription_id integer,
  start_date timestamptz,
  end_date timestamptz,
  payment_id text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);

create index if not exists user_subscriptions_user_idx on public.user_subscriptions (user_id);
create index if not exists user_subscriptions_status_idx on public.user_subscriptions (status);
create index if not exists user_subscriptions_plan_idx on public.user_subscriptions (plan_id);
create index if not exists user_subscriptions_ends_at_idx on public.user_subscriptions (ends_at);
create index if not exists user_subscriptions_created_at_idx on public.user_subscriptions (created_at desc);

-- Prevent multiple concurrently-active subscriptions per user.
create unique index if not exists user_subscriptions_one_active_idx
  on public.user_subscriptions (user_id)
  where status = 'active';

alter table public.user_subscriptions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_subscriptions'
      and policyname = 'deny_all_user_subscriptions'
  ) then
    create policy deny_all_user_subscriptions
      on public.user_subscriptions
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Helper RPC for admin dashboard counts
create or replace function public.subscription_plan_counts(p_country_code text default null)
returns table (
  plan_id text,
  active_count bigint
)
language sql
stable
as $$
  select s.plan_id, count(*)::bigint as active_count
  from public.user_subscriptions s
  where s.status = 'active'
    and (p_country_code is null or s.country_code = p_country_code)
  group by s.plan_id
  order by s.plan_id
$$;

-- Hint PostgREST to refresh its schema cache after creating subscription tables.
notify pgrst, 'reload schema';

-- TRACKS
create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist text not null,
  audio_url text not null,
  artwork_url text,
  country text,
  genre text,
  language text,
  duration_ms integer,
  created_at timestamptz not null default now()
);

-- If your tracks table already existed, keep it upgrade-safe.
alter table public.tracks add column if not exists country text;
alter table public.tracks add column if not exists genre text;
alter table public.tracks add column if not exists language text;

create index if not exists tracks_created_at_idx on public.tracks (created_at desc);

do $$
begin
  create unique index tracks_audio_url_unique on public.tracks (audio_url);
exception
  when duplicate_object then null;
  when duplicate_table then null;
  when unique_violation then
    raise notice 'Could not create unique index tracks_audio_url_unique because public.tracks contains duplicate audio_url values. Dedupe tracks by audio_url, then re-run: create unique index tracks_audio_url_unique on public.tracks (audio_url);';
end $$;

-- NOTIFICATIONS (optional)
-- Uses TEXT user_id (Firebase UID) to avoid coupling to auth.users.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  title text,
  body text,
  type text,
  user_id text,
  created_at timestamptz not null default now()
);

create index if not exists notifications_created_at_idx on public.notifications (created_at desc);

-- EVENTS / LIVE SESSIONS
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('live','event')),
  title text not null,
  subtitle text,
  city text,
  starts_at timestamptz,
  is_live boolean not null default false,
  created_at timestamptz not null default now()
);

-- LIVE SCHEDULING (compat)
-- Some clients expect a dedicated `live_sessions` table for scheduling/moderation.
create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  channel_name text,
  host_type text not null default 'dj' check (host_type in ('dj','artist')),
  host_id text,
  host_firebase_uid text,
  stream_type text not null default 'dj_live' check (stream_type in ('dj_live','artist_live','battle')),
  title text,
  description text,
  status text not null default 'scheduled' check (status in ('scheduled','live','ended','canceled')),
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  region text not null default 'MW',
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists live_sessions_status_idx on public.live_sessions (status);
create index if not exists live_sessions_region_idx on public.live_sessions (region);
create index if not exists live_sessions_scheduled_start_idx on public.live_sessions (scheduled_start_at desc);
create index if not exists live_sessions_started_at_idx on public.live_sessions (started_at desc);
create index if not exists live_sessions_host_idx on public.live_sessions (host_type, host_id);
create index if not exists live_sessions_host_firebase_uid_idx on public.live_sessions (host_firebase_uid);
create index if not exists live_sessions_channel_name_idx on public.live_sessions (channel_name);

alter table public.live_sessions enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'deny_all_live_sessions'
  ) then
    create policy deny_all_live_sessions
      on public.live_sessions
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Consumer app is READ-ONLY for events: allow SELECT but NOT insert/update/delete.
grant select on table public.events to anon, authenticated;

-- TICKETS / ORDERS
-- Stored server-side only (Edge Function uses service role).
-- Uses TEXT user_id (Firebase UID) to avoid coupling to auth.users.
create table if not exists public.ticket_orders (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  event_id uuid not null references public.events (id) on delete cascade,
  qty integer not null default 1 check (qty >= 1 and qty <= 20),
  amount_mwk integer not null default 0 check (amount_mwk >= 0),
  currency text not null default 'MWK',
  status text not null default 'created' check (status in ('created','pending','paid','cancelled','failed','refunded')),
  provider text,
  provider_ref text,
  checkout_url text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

-- Upgrade safety: if ticket_orders already existed, ensure columns used by indexes exist.
alter table public.ticket_orders add column if not exists status text;
alter table public.ticket_orders add column if not exists created_at timestamptz;
alter table public.ticket_orders alter column created_at set default now();
update public.ticket_orders set created_at = coalesce(created_at, now()) where created_at is null;
alter table public.ticket_orders alter column status set default 'created';

create index if not exists ticket_orders_user_created_at_idx
  on public.ticket_orders (user_id, created_at desc);

create index if not exists ticket_orders_event_created_at_idx
  on public.ticket_orders (event_id, created_at desc);

create index if not exists ticket_orders_status_created_at_idx
  on public.ticket_orders (status, created_at desc);

-- VIDEOS
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  video_url text not null,
  thumbnail_url text,
  created_at timestamptz not null default now()
);

-- CREATOR PROFILES (Artists & DJs)
-- Consumer app directory for artist/dj discovery.
-- Uses TEXT user_id (Firebase UID) to avoid coupling to auth.users.
create table if not exists public.creator_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  role text not null check (role in ('artist','dj')),
  display_name text not null,
  avatar_url text,
  bio text,
  created_at timestamptz not null default now(),

  unique (user_id)
);

create index if not exists creator_profiles_role_created_at_idx
  on public.creator_profiles (role, created_at desc);

-- For Firebase-auth apps, keep this table RLS-disabled unless you are
-- provisioning through a trusted backend.
alter table public.creator_profiles disable row level security;

-- Allow the app to auto-provision a creator profile after Firebase login.
-- NOTE: This app uses Firebase Auth (not Supabase Auth), so RLS policies
-- cannot safely restrict writes by auth.uid(). Consider provisioning via a
-- trusted backend if you need strict security.
grant select, insert, update on table public.creator_profiles to anon, authenticated;

-- RECENT CONTEXTS (Quick Access)
-- Spotify-style: small rounded "memory" cards based on what the user recently played.
-- Uses TEXT user_id (Firebase UID) to avoid coupling to auth.users.
create table if not exists public.recent_contexts (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  context_type text not null, -- playlist | genre | radio | dj_set | track | smart_playlist
  context_id text not null,
  title text not null,
  image_url text,
  source text default 'music',
  last_played_at timestamptz default now(),

  unique (user_id, context_id)
);

create index if not exists recent_contexts_user_last_played_idx
  on public.recent_contexts (user_id, last_played_at desc);

create index if not exists recent_contexts_user_source_last_played_idx
  on public.recent_contexts (user_id, source, last_played_at desc);

-- Grants: RLS policies are required but not sufficient; roles also need table privileges.
grant select, insert, update on table public.recent_contexts to anon, authenticated;

-- PLAYLISTS (Spotify-style user playlists)
-- NOTE: This app uses Firebase Auth, not Supabase Auth. We store user_id as TEXT
-- (Firebase UID or a device UUID fallback) to avoid auth.users coupling.
create table if not exists public.playlists (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  name text not null,
  cover_url text,
  created_at timestamptz not null default now()
);

create index if not exists playlists_user_created_at_idx
  on public.playlists (user_id, created_at desc);

-- SONGS (legacy catalog)
-- Some parts of the app still read from songs and playlist_songs.
-- The FK below requires songs.id to be UNIQUE or a PRIMARY KEY.
-- If your songs table already exists, this block will try to add a unique
-- index (or PK) on id in an upgrade-safe way.
create table if not exists public.songs (
  id uuid primary key default gen_random_uuid(),
  title text,
  audio_url text,
  thumbnail_url text,
  image_url text,
  duration integer,
  duration_seconds integer,
  created_at timestamptz not null default now()
);

do $$
begin
  -- If songs exists but was created without a PK/unique constraint on id,
  -- add one so foreign keys + PostgREST embedding work.
  begin
    alter table public.songs
      add constraint songs_pkey primary key (id);
  exception
    when duplicate_object then null;
    when invalid_table_definition then null;
    when undefined_column then null;
  end;

  begin
    create unique index if not exists songs_id_unique on public.songs (id);
  exception
    when unique_violation then
      raise notice 'Could not create songs_id_unique because public.songs contains duplicate id values. Dedupe songs.id, then re-run schema.';
    when undefined_column then null;
  end;
end $$;

create table if not exists public.playlist_songs (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  song_id uuid not null references public.songs(id) on delete cascade,
  position int,
  created_at timestamptz not null default now(),

  unique (playlist_id, song_id)
);

create index if not exists playlist_songs_playlist_position_idx
  on public.playlist_songs (playlist_id, position asc);

create index if not exists playlist_songs_playlist_created_at_idx
  on public.playlist_songs (playlist_id, created_at desc);

-- Tracks-based playlists (primary app playback model)
create table if not exists public.playlist_tracks (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  position int,
  created_at timestamptz not null default now(),

  unique (playlist_id, track_id)
);

create index if not exists playlist_tracks_playlist_position_idx
  on public.playlist_tracks (playlist_id, position asc);

create index if not exists playlist_tracks_playlist_created_at_idx
  on public.playlist_tracks (playlist_id, created_at desc);

-- Upgrade safety: ensure the position column exists and backfill nulls
-- so manual reordering works deterministically.
alter table public.playlist_tracks add column if not exists position int;
alter table public.playlist_tracks alter column position set default 0;

with ranked as (
  select
    id,
    row_number() over (
      partition by playlist_id
      order by created_at asc, id asc
    ) - 1 as rn
  from public.playlist_tracks
  where position is null
)
update public.playlist_tracks pt
set position = ranked.rn
from ranked
where pt.id = ranked.id;

grant select, insert, update, delete on table public.playlists to anon, authenticated;
grant select, insert, update, delete on table public.playlist_songs to anon, authenticated;
grant select, insert, update, delete on table public.playlist_tracks to anon, authenticated;

-- If you already had a videos table from earlier experiments, these ALTERs make the schema upgrade safe.
alter table public.videos add column if not exists title text;
alter table public.videos add column if not exists video_url text;
alter table public.videos add column if not exists thumbnail_url text;
alter table public.videos add column if not exists created_at timestamptz;

update public.videos
set created_at = coalesce(created_at, now())
where created_at is null;

-- Enforce constraints only after columns exist.
alter table public.videos
  alter column title set not null;

alter table public.videos
  alter column video_url set not null;

do $$
begin
  create unique index videos_video_url_unique on public.videos (video_url);
exception
  when duplicate_object then null;
end $$;

create index if not exists videos_created_at_idx on public.videos (created_at desc);

-- If you already had an events table from earlier experiments, it may be
-- missing some columns (e.g. kind). These ALTERs make the schema upgrade safe.
alter table public.events add column if not exists kind text;
alter table public.events add column if not exists title text;
alter table public.events add column if not exists subtitle text;
alter table public.events add column if not exists city text;
alter table public.events add column if not exists starts_at timestamptz;
alter table public.events add column if not exists is_live boolean;
alter table public.events add column if not exists created_at timestamptz;

update public.events
set kind = coalesce(kind, 'event')
where kind is null;

update public.events
set is_live = coalesce(is_live, false)
where is_live is null;

update public.events
set created_at = coalesce(created_at, now())
where created_at is null;

-- Enforce constraints only after the column exists.
alter table public.events
  alter column kind set not null;

alter table public.events
  alter column is_live set not null;

alter table public.events
  alter column is_live set default false;

do $$
begin
  alter table public.events
    add constraint events_kind_check check (kind in ('live','event'));
exception
  when duplicate_object then null;
end $$;

create index if not exists events_created_at_idx on public.events (created_at desc);
create index if not exists events_kind_idx on public.events (kind);

-- Note: Enable RLS + policies based on your app needs.
-- For a public prototype, you can start with read-only policies.

-- Optional: basic read-only policies (recommended for client apps)
-- If RLS is already enabled on these tables, these policies will fix "permission denied" / RLS blocks.
-- If RLS is disabled, these policies are harmless.

alter table public.tracks enable row level security;
drop policy if exists "Public read tracks" on public.tracks;
create policy "Public read tracks" on public.tracks
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write tracks" on public.tracks;
create policy "Public write tracks" on public.tracks
  for insert
  to anon, authenticated
  with check (
    title is not null and length(title) > 0 and
    artist is not null and length(artist) > 0 and
    audio_url is not null and length(audio_url) > 0
  );

grant select, insert on table public.tracks to anon, authenticated;

alter table public.events enable row level security;
drop policy if exists "Public read events" on public.events;
create policy "Public read events" on public.events
  for select
  to anon, authenticated
  using (true);

alter table public.notifications enable row level security;
drop policy if exists "Public read notifications" on public.notifications;
create policy "Public read notifications" on public.notifications
  for select
  to anon, authenticated
  using (true);

alter table public.videos enable row level security;
drop policy if exists "Public read videos" on public.videos;
create policy "Public read videos" on public.videos
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write videos" on public.videos;
create policy "Public write videos" on public.videos
  for insert
  to anon, authenticated
  with check (
    title is not null and length(title) > 0 and
    video_url is not null and length(video_url) > 0
  );

grant select, insert on table public.videos to anon, authenticated;

alter table public.recent_contexts enable row level security;
drop policy if exists "Public read recent contexts" on public.recent_contexts;
create policy "Public read recent contexts" on public.recent_contexts
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write recent contexts" on public.recent_contexts;
create policy "Public write recent contexts" on public.recent_contexts
  for insert
  to anon, authenticated
  with check (user_id is not null);

drop policy if exists "Public update recent contexts" on public.recent_contexts;
create policy "Public update recent contexts" on public.recent_contexts
  for update
  to anon, authenticated
  using (true)
  with check (user_id is not null);

alter table public.playlists enable row level security;
drop policy if exists "Public read playlists" on public.playlists;
create policy "Public read playlists" on public.playlists
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write playlists" on public.playlists;
create policy "Public write playlists" on public.playlists
  for insert
  to anon, authenticated
  with check (user_id is not null);

drop policy if exists "Public update playlists" on public.playlists;
create policy "Public update playlists" on public.playlists
  for update
  to anon, authenticated
  using (true)
  with check (user_id is not null);

drop policy if exists "Public delete playlists" on public.playlists;
create policy "Public delete playlists" on public.playlists
  for delete
  to anon, authenticated
  using (true);

alter table public.playlist_songs enable row level security;
drop policy if exists "Public read playlist songs" on public.playlist_songs;
create policy "Public read playlist songs" on public.playlist_songs
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write playlist songs" on public.playlist_songs;
create policy "Public write playlist songs" on public.playlist_songs
  for insert
  to anon, authenticated
  with check (playlist_id is not null and song_id is not null);

drop policy if exists "Public update playlist songs" on public.playlist_songs;
create policy "Public update playlist songs" on public.playlist_songs
  for update
  to anon, authenticated
  using (true)
  with check (playlist_id is not null and song_id is not null);

drop policy if exists "Public delete playlist songs" on public.playlist_songs;
create policy "Public delete playlist songs" on public.playlist_songs
  for delete
  to anon, authenticated
  using (true);

alter table public.playlist_tracks enable row level security;
drop policy if exists "Public read playlist tracks" on public.playlist_tracks;
create policy "Public read playlist tracks" on public.playlist_tracks
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write playlist tracks" on public.playlist_tracks;
create policy "Public write playlist tracks" on public.playlist_tracks
  for insert
  to anon, authenticated
  with check (true);

drop policy if exists "Public update playlist tracks" on public.playlist_tracks;
create policy "Public update playlist tracks" on public.playlist_tracks
  for update
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "Public delete playlist tracks" on public.playlist_tracks;
create policy "Public delete playlist tracks" on public.playlist_tracks
  for delete
  to anon, authenticated
  using (true);

-- PULSE ENGAGEMENT (likes, comments, follows)
-- NOTE: The Flutter app currently uses Firebase Auth, not Supabase Auth.
-- These tables store user_id as TEXT (Firebase UID) so you can persist
-- engagement across devices for the same Firebase account.

create table if not exists public.pulse_likes (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos(id) on delete cascade,
  user_id text not null,
  liked boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  create unique index pulse_likes_unique on public.pulse_likes (video_id, user_id);
exception
  when duplicate_object then null;
end $$;

create index if not exists pulse_likes_video_id_idx on public.pulse_likes (video_id);
create index if not exists pulse_likes_user_id_idx on public.pulse_likes (user_id);
create index if not exists pulse_likes_created_at_idx on public.pulse_likes (created_at desc);

create table if not exists public.pulse_comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos(id) on delete cascade,
  user_id text not null,
  comment text not null,
  created_at timestamptz not null default now()
);

create index if not exists pulse_comments_video_id_idx on public.pulse_comments (video_id);
create index if not exists pulse_comments_user_id_idx on public.pulse_comments (user_id);
create index if not exists pulse_comments_created_at_idx on public.pulse_comments (created_at desc);

create table if not exists public.pulse_follows (
  id uuid primary key default gen_random_uuid(),
  artist_id text not null,
  user_id text not null,
  following boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  create unique index pulse_follows_unique on public.pulse_follows (artist_id, user_id);
exception
  when duplicate_object then null;
end $$;

create index if not exists pulse_follows_artist_id_idx on public.pulse_follows (artist_id);
create index if not exists pulse_follows_user_id_idx on public.pulse_follows (user_id);
create index if not exists pulse_follows_created_at_idx on public.pulse_follows (created_at desc);

-- RLS + policies
-- IMPORTANT: With only an anon key, the DB cannot truly verify Firebase UIDs.
-- These policies are suitable for prototypes. For real security, move writes to
-- an Edge Function that verifies Firebase ID tokens, or use Supabase Auth.

alter table public.pulse_likes enable row level security;
drop policy if exists "Public read pulse likes" on public.pulse_likes;
create policy "Public read pulse likes" on public.pulse_likes
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write pulse likes" on public.pulse_likes;
create policy "Public write pulse likes" on public.pulse_likes
  for insert
  to anon, authenticated
  with check (user_id is not null and length(user_id) > 0);

drop policy if exists "Public update pulse likes" on public.pulse_likes;
create policy "Public update pulse likes" on public.pulse_likes
  for update
  to anon, authenticated
  using (true)
  with check (user_id is not null and length(user_id) > 0);

alter table public.pulse_comments enable row level security;
drop policy if exists "Public read pulse comments" on public.pulse_comments;
create policy "Public read pulse comments" on public.pulse_comments
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write pulse comments" on public.pulse_comments;
create policy "Public write pulse comments" on public.pulse_comments
  for insert
  to anon, authenticated
  with check (user_id is not null and length(user_id) > 0);

alter table public.pulse_follows enable row level security;
drop policy if exists "Public read pulse follows" on public.pulse_follows;
create policy "Public read pulse follows" on public.pulse_follows
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Public write pulse follows" on public.pulse_follows;
create policy "Public write pulse follows" on public.pulse_follows
  for insert
  to anon, authenticated
  with check (user_id is not null and length(user_id) > 0);

drop policy if exists "Public update pulse follows" on public.pulse_follows;
create policy "Public update pulse follows" on public.pulse_follows
  for update
  to anon, authenticated
  using (true)
  with check (user_id is not null and length(user_id) > 0);

-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';
