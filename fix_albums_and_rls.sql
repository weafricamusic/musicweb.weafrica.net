-- Fix missing albums table and RLS issues
-- Run this in Supabase SQL editor

-- Fix missing albums table and RLS issues
-- Run this in Supabase SQL editor

-- 1) Create albums table if missing
CREATE TABLE IF NOT EXISTS public.albums (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL,
  artist_uid text,
  title text NOT NULL,
  description text,
  cover_url text,
  visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('public', 'private')),
  is_active boolean NOT NULL DEFAULT true,
  is_published boolean NOT NULL DEFAULT false,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS artist_uid text;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS cover_url text;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('public', 'private'));
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT false;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS published_at timestamptz;
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.albums ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_albums_is_published ON public.albums (is_published);
CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON public.albums (artist_id);
CREATE INDEX IF NOT EXISTS idx_albums_artist_uid ON public.albums (artist_uid);

-- RLS
ALTER TABLE public.albums ENABLE ROW LEVEL SECURITY;

-- Policies (MVP allow all)
DROP POLICY IF EXISTS mvp_public_all ON public.albums;
CREATE POLICY mvp_public_all ON public.albums FOR ALL USING (true) WITH CHECK (true);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.albums TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.dj_playlists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dj_uid text NOT NULL,
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.dj_playlists ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.dj_playlists ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.dj_playlists ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.dj_playlists ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS dj_playlists_dj_uid_created_at_idx ON public.dj_playlists (dj_uid, created_at DESC);

ALTER TABLE public.dj_playlists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.dj_playlists;
CREATE POLICY mvp_public_all ON public.dj_playlists FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dj_playlists TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.dj_playlist_tracks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id uuid NOT NULL REFERENCES public.dj_playlists(id) ON DELETE CASCADE,
  song_id text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (playlist_id, song_id)
);

CREATE INDEX IF NOT EXISTS dj_playlist_tracks_playlist_pos_idx ON public.dj_playlist_tracks (playlist_id, position ASC);

ALTER TABLE public.dj_playlist_tracks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.dj_playlist_tracks;
CREATE POLICY mvp_public_all ON public.dj_playlist_tracks FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dj_playlist_tracks TO anon, authenticated;
CREATE TABLE IF NOT EXISTS public.dj_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dj_uid text NOT NULL,
  stage_name text,
  country text,
  bio text,
  profile_photo text,
  followers_count bigint NOT NULL DEFAULT 0,
  bank_account text,
  mobile_money_phone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (dj_uid)
);

-- Add missing columns if table exists
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS stage_name text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS country text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS bio text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS profile_photo text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS followers_count bigint NOT NULL DEFAULT 0;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS bank_account text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS mobile_money_phone text;
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.dj_profile ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS dj_profile_dj_uid_idx ON public.dj_profile (dj_uid);

ALTER TABLE public.dj_profile ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.dj_profile;
CREATE POLICY mvp_public_all ON public.dj_profile FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dj_profile TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.dj_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dj_uid text NOT NULL,
  title text NOT NULL,
  genre text,
  duration integer,
  audio_url text NOT NULL,
  plays bigint NOT NULL DEFAULT 0,
  likes bigint NOT NULL DEFAULT 0,
  comments bigint NOT NULL DEFAULT 0,
  coins_earned bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS genre text;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS duration integer;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS audio_url text;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS plays bigint NOT NULL DEFAULT 0;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS likes bigint NOT NULL DEFAULT 0;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS comments bigint NOT NULL DEFAULT 0;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS coins_earned bigint NOT NULL DEFAULT 0;
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.dj_sets ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS dj_sets_dj_uid_created_at_idx ON public.dj_sets (dj_uid, created_at DESC);

ALTER TABLE public.dj_sets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.dj_sets;
CREATE POLICY mvp_public_all ON public.dj_sets FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dj_sets TO anon, authenticated;

-- Extend messages and boosts for DJ
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL,
  artist_uid text,
  dj_uid text,
  sender_id text,
  sender_name text,
  message text,
  read boolean NOT NULL DEFAULT false,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS artist_uid text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_id text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_name text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS message text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read boolean NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS messages_artist_uid_created_at_idx ON public.messages (artist_uid, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_artist_id_created_at_idx ON public.messages (artist_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_dj_uid_created_at_idx ON public.messages (dj_uid, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_read_idx ON public.messages (read, created_at DESC);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.messages;
CREATE POLICY mvp_public_all ON public.messages FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.messages TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.boosts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL,
  artist_uid text,
  dj_uid text,
  song_id text,
  video_id text,
  content_id text,
  content_type text,
  coins_budget bigint NOT NULL DEFAULT 0,
  country_target text,
  start_date date,
  end_date date,
  reach bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS artist_id uuid REFERENCES public.artists(id) ON DELETE SET NULL;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS artist_uid text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS song_id text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS video_id text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS content_id text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS content_type text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS coins_budget bigint NOT NULL DEFAULT 0;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS country_target text;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS start_date date;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS end_date date;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS reach bigint NOT NULL DEFAULT 0;
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed','cancelled'));
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.boosts ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS boosts_artist_uid_created_at_idx ON public.boosts (artist_uid, created_at DESC);
CREATE INDEX IF NOT EXISTS boosts_artist_id_created_at_idx ON public.boosts (artist_id, created_at DESC);
CREATE INDEX IF NOT EXISTS boosts_dj_uid_created_at_idx ON public.boosts (dj_uid, created_at DESC);
CREATE INDEX IF NOT EXISTS boosts_song_id_idx ON public.boosts (song_id);
CREATE INDEX IF NOT EXISTS boosts_video_id_idx ON public.boosts (video_id);

ALTER TABLE public.boosts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.boosts;
CREATE POLICY mvp_public_all ON public.boosts FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.boosts TO anon, authenticated;

-- 3) Fix creator_profiles RLS
-- If RLS is enabled but no policies, add them
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'creator_profiles' AND c.relrowsecurity = true
  ) THEN
    -- Enable RLS and add policies
    DROP POLICY IF EXISTS creator_profiles_public_all ON public.creator_profiles;
    CREATE POLICY creator_profiles_public_all ON public.creator_profiles FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Grants for creator_profiles
GRANT SELECT, INSERT, UPDATE, DELETE ON public.creator_profiles TO anon, authenticated;

-- 4) Withdrawal requests table
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dj_uid text NOT NULL,
  amount numeric NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'USD' CHECK (currency IN ('USD', 'MWK', 'ZAR')),
  payment_method text NOT NULL CHECK (payment_method IN ('bank', 'mobile_money')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS dj_uid text;
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS amount numeric CHECK (amount > 0);
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'USD' CHECK (currency IN ('USD', 'MWK', 'ZAR'));
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS payment_method text CHECK (payment_method IN ('bank', 'mobile_money'));
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed'));
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS withdrawal_requests_dj_uid_created_at_idx ON public.withdrawal_requests (dj_uid, created_at DESC);

ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.withdrawal_requests;
CREATE POLICY mvp_public_all ON public.withdrawal_requests FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.withdrawal_requests TO anon, authenticated;

-- 5) Ads table for audio ads
CREATE TABLE IF NOT EXISTS public.ads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  audio_url text NOT NULL,
  duration_seconds integer,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add missing columns if table exists
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS audio_url text;
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS duration_seconds integer;
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.ads ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS ads_is_active_created_at_idx ON public.ads (is_active, created_at DESC);

ALTER TABLE public.ads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvp_public_all ON public.ads;
CREATE POLICY mvp_public_all ON public.ads FOR ALL USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ads TO anon, authenticated;