-- STEP 6: DJ approval system
-- Adds `approved` boolean to `djs` with default false.

create extension if not exists pgcrypto;

create table if not exists public.djs (
	id uuid primary key default gen_random_uuid(),
	created_at timestamptz not null default now(),
	approved boolean not null default false
);

alter table public.djs
add column if not exists approved boolean not null default false;
