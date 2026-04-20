-- Consumer content access metadata
--
-- Adds minimal columns needed for in-app gating:
-- - songs/videos: is_exclusive
-- - live sessions/battles: access_tier (watch_only|standard|priority)

alter table if exists public.songs
  add column if not exists is_exclusive boolean not null default false;

alter table if exists public.videos
  add column if not exists is_exclusive boolean not null default false;

alter table if exists public.live_sessions
  add column if not exists access_tier text not null default 'standard';

alter table if exists public.live_battles
  add column if not exists access_tier text not null default 'standard';
