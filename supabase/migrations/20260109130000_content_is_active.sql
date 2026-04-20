-- STEP 8: Content moderation flags
-- Adds `is_active` boolean to songs and videos (default true).
create extension if not exists pgcrypto;

create table if not exists public.songs (
	id uuid primary key default gen_random_uuid(),
	user_id text,
	created_at timestamptz not null default now(),
	is_active boolean not null default true,
	approved boolean not null default false
);

create table if not exists public.videos (
	id uuid primary key default gen_random_uuid(),
	user_id text,
	created_at timestamptz not null default now(),
	is_active boolean not null default true,
	approved boolean not null default false
);

alter table public.songs
add column if not exists is_active boolean not null default true;
alter table public.videos
add column if not exists is_active boolean not null default true;
