-- Featured artists (admin-managed)
-- Used for discovery surfaces and growth promotion.

-- Needed for gen_random_uuid()
create extension if not exists pgcrypto;
-- Ensure helper for updated_at exists.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;
create table if not exists public.featured_artists (
	id uuid primary key default gen_random_uuid(),
	artist_id uuid not null references public.artists(id) on delete cascade,
	country_code text null,
	priority integer not null default 0,
	is_active boolean not null default true,
	starts_at timestamptz null,
	ends_at timestamptz null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (artist_id)
);
-- If table existed already, ensure columns exist (for idempotent apply).
do $$
begin
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='country_code') then
		alter table public.featured_artists add column country_code text null;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='priority') then
		alter table public.featured_artists add column priority integer not null default 0;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='is_active') then
		alter table public.featured_artists add column is_active boolean not null default true;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='created_at') then
		alter table public.featured_artists add column created_at timestamptz not null default now();
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='updated_at') then
		alter table public.featured_artists add column updated_at timestamptz not null default now();
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='starts_at') then
		alter table public.featured_artists add column starts_at timestamptz null;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='featured_artists' and column_name='ends_at') then
		alter table public.featured_artists add column ends_at timestamptz null;
	end if;
end $$;
create index if not exists featured_artists_country_code_idx on public.featured_artists (country_code);
create index if not exists featured_artists_active_priority_idx on public.featured_artists (is_active, priority desc, created_at desc);
create index if not exists featured_artists_artist_id_idx on public.featured_artists (artist_id);
do $$
begin
	if not exists (select 1 from pg_trigger where tgname = 'featured_artists_set_updated_at') then
		create trigger featured_artists_set_updated_at
		before update on public.featured_artists
		for each row
		execute function public.tg_set_updated_at();
	end if;
end $$;
-- Public read access (active only, and within optional scheduling).
alter table public.featured_artists enable row level security;
drop policy if exists "Public can read active featured artists" on public.featured_artists;
create policy "Public can read active featured artists" on public.featured_artists
	for select
	using (
		is_active = true
		and (starts_at is null or starts_at <= now())
		and (ends_at is null or ends_at >= now())
	);
-- Refresh PostgREST schema cache (helps avoid transient PGRST205 after migrations)
notify pgrst, 'reload schema';
