-- Curated playlists (admin-managed)
-- Designed to be flexible across evolving content schemas.

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

create table if not exists public.playlists (
	id uuid primary key default gen_random_uuid(),
	title text not null,
	description text null,
	image_url text null,
	country_code text null,
	priority integer not null default 0,
	is_active boolean not null default true,
	starts_at timestamptz null,
	ends_at timestamptz null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

-- If table existed already, ensure columns exist (for idempotent apply).
do $$
begin
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='priority') then
		alter table public.playlists add column priority integer not null default 0;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='is_active') then
		alter table public.playlists add column is_active boolean not null default true;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='created_at') then
		alter table public.playlists add column created_at timestamptz not null default now();
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='updated_at') then
		alter table public.playlists add column updated_at timestamptz not null default now();
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='starts_at') then
		alter table public.playlists add column starts_at timestamptz null;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='ends_at') then
		alter table public.playlists add column ends_at timestamptz null;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlists' and column_name='country_code') then
		alter table public.playlists add column country_code text null;
	end if;
end $$;

create index if not exists playlists_country_code_idx on public.playlists (country_code);
create index if not exists playlists_active_priority_idx on public.playlists (is_active, priority desc, created_at desc);


do $$
begin
	if not exists (select 1 from pg_trigger where tgname = 'playlists_set_updated_at') then
		create trigger playlists_set_updated_at
		before update on public.playlists
		for each row
		execute function public.tg_set_updated_at();
	end if;
end $$;

-- Playlist items (track/video/etc). Item IDs are stored as text for schema flexibility.
create table if not exists public.playlist_items (
	id uuid primary key default gen_random_uuid(),
	playlist_id uuid not null references public.playlists(id) on delete cascade,
	item_type text not null,
	item_id text not null,
	position integer not null default 0,
	is_active boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (playlist_id, item_type, item_id)
);

-- If table existed already, ensure columns exist.
do $$
begin
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlist_items' and column_name='position') then
		alter table public.playlist_items add column position integer not null default 0;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlist_items' and column_name='is_active') then
		alter table public.playlist_items add column is_active boolean not null default true;
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlist_items' and column_name='created_at') then
		alter table public.playlist_items add column created_at timestamptz not null default now();
	end if;
	if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='playlist_items' and column_name='updated_at') then
		alter table public.playlist_items add column updated_at timestamptz not null default now();
	end if;
end $$;

create index if not exists playlist_items_playlist_pos_idx on public.playlist_items (playlist_id, position asc);


do $$
begin
	if not exists (select 1 from pg_trigger where tgname = 'playlist_items_set_updated_at') then
		create trigger playlist_items_set_updated_at
		before update on public.playlist_items
		for each row
		execute function public.tg_set_updated_at();
	end if;
end $$;

-- Public read access (active only, and within optional scheduling).
alter table public.playlists enable row level security;
alter table public.playlist_items enable row level security;

-- Drop + recreate to keep idempotent.
drop policy if exists "Public can read active playlists" on public.playlists;
create policy "Public can read active playlists" on public.playlists
	for select
	using (
		is_active = true
		and (starts_at is null or starts_at <= now())
		and (ends_at is null or ends_at >= now())
	);


drop policy if exists "Public can read active playlist items" on public.playlist_items;
create policy "Public can read active playlist items" on public.playlist_items
	for select
	using (
		is_active = true
		and exists (
			select 1
			from public.playlists p
			where p.id = playlist_id
				and p.is_active = true
				and (p.starts_at is null or p.starts_at <= now())
				and (p.ends_at is null or p.ends_at >= now())
		)
	);

-- Refresh PostgREST schema cache (helps avoid transient PGRST205 after migrations)
notify pgrst, 'reload schema';
