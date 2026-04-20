-- Creates live sessions table for scheduling/live history (artist dashboard compatibility).
-- Safe to run multiple times.
--
-- Note: This repo already has a more feature-complete `public.live_sessions` used by other flows.
-- This migration is additive: it ensures the artist-dashboard columns + indexes exist.

create extension if not exists pgcrypto;

-- If `live_sessions` doesn't exist (e.g. partial/standalone schema), create a minimal table.
create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),

  -- Firebase artist UID
  artist_uid text not null,

  -- scheduled | live | ended | cancelled
  status text not null default 'scheduled',

  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,

  event_url text,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint live_sessions_status_check check (status in ('scheduled', 'live', 'ended', 'cancelled'))
);

-- In the main production schema, `public.live_sessions` may already exist with a different shape.
-- Ensure the artist-dashboard columns exist (without forcing NOT NULL on legacy rows).
alter table if exists public.live_sessions
  add column if not exists artist_uid text,
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists event_url text,
  add column if not exists notes text;

create index if not exists live_sessions_artist_uid_idx on public.live_sessions (artist_uid);
create index if not exists live_sessions_starts_at_idx on public.live_sessions (starts_at desc);
create index if not exists live_sessions_artist_uid_starts_at_idx on public.live_sessions (artist_uid, starts_at desc);

alter table public.live_sessions enable row level security;
