-- Genres & Categories taxonomy tables for content tagging.
-- Admin writes happen via service role; public reads are allowed for active rows.

-- Ensure helper for updated_at exists (used across the schema).
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;

create table if not exists public.genres (
	id uuid primary key default gen_random_uuid(),
	name text not null,
	is_active boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

-- If the table already existed, ensure required columns exist.
do $$
begin
	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'genres' and column_name = 'is_active'
	) then
		alter table public.genres add column is_active boolean not null default true;
	end if;

	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'genres' and column_name = 'created_at'
	) then
		alter table public.genres add column created_at timestamptz not null default now();
	end if;

	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'genres' and column_name = 'updated_at'
	) then
		alter table public.genres add column updated_at timestamptz not null default now();
	end if;
end $$;

create unique index if not exists genres_name_key on public.genres (lower(name));

do $$
begin
	if not exists (select 1 from pg_trigger where tgname = 'genres_set_updated_at') then
		create trigger genres_set_updated_at
		before update on public.genres
		for each row
		execute function public.tg_set_updated_at();
	end if;
end $$;

create table if not exists public.categories (
	id uuid primary key default gen_random_uuid(),
	name text not null,
	is_active boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

-- If the table already existed, ensure required columns exist.
do $$
begin
	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'categories' and column_name = 'is_active'
	) then
		alter table public.categories add column is_active boolean not null default true;
	end if;

	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'categories' and column_name = 'created_at'
	) then
		alter table public.categories add column created_at timestamptz not null default now();
	end if;

	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public' and table_name = 'categories' and column_name = 'updated_at'
	) then
		alter table public.categories add column updated_at timestamptz not null default now();
	end if;
end $$;

create unique index if not exists categories_name_key on public.categories (lower(name));

do $$
begin
	if not exists (select 1 from pg_trigger where tgname = 'categories_set_updated_at') then
		create trigger categories_set_updated_at
		before update on public.categories
		for each row
		execute function public.tg_set_updated_at();
	end if;
end $$;

-- Public read access (active only). Writes are expected via service role.
alter table public.genres enable row level security;
alter table public.categories enable row level security;

-- Drop + recreate to keep this migration idempotent.
drop policy if exists "Public can read active genres" on public.genres;
create policy "Public can read active genres" on public.genres
	for select
	using (is_active = true);


drop policy if exists "Public can read active categories" on public.categories;
create policy "Public can read active categories" on public.categories
	for select
	using (is_active = true);
