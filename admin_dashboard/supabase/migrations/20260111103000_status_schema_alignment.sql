-- Align schema with admin control fields (non-breaking; keeps legacy `approved` columns).

create extension if not exists pgcrypto;

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  firebase_uid text,
  username text,
  email text,
  status text not null default 'active',
  region text,
  created_at timestamptz not null default now()
);

-- USERS
alter table public.users
  add column if not exists firebase_uid text,
  add column if not exists username text,
  add column if not exists email text,
  add column if not exists status text not null default 'active',
  add column if not exists region text;

create index if not exists users_firebase_uid_idx on public.users (firebase_uid);
create index if not exists users_status_idx on public.users (status);

-- ARTISTS
alter table public.artists
  add column if not exists firebase_uid text,
  add column if not exists stage_name text,
  add column if not exists status text not null default 'pending',
  add column if not exists blocked boolean not null default false,
  add column if not exists verified boolean not null default false,
  add column if not exists region text;

create index if not exists artists_firebase_uid_idx on public.artists (firebase_uid);
create index if not exists artists_status_idx on public.artists (status);

-- DJS
alter table public.djs
  add column if not exists firebase_uid text,
  add column if not exists dj_name text,
  add column if not exists status text not null default 'pending',
  add column if not exists blocked boolean not null default false,
  add column if not exists can_go_live boolean not null default false,
  add column if not exists region text;

create index if not exists djs_firebase_uid_idx on public.djs (firebase_uid);
create index if not exists djs_status_idx on public.djs (status);

-- Backfill status fields from legacy booleans when present.

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='artists' and column_name='approved') then
    update public.artists
      set status = case
        when coalesce(blocked,false) = true then 'blocked'
        when coalesce(approved,false) = true then 'active'
        else 'pending'
      end
      where coalesce(nullif(status,''), '') = '';
  end if;

  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='djs' and column_name='approved') then
    update public.djs
      set status = case
        when coalesce(blocked,false) = true then 'blocked'
        when coalesce(approved,false) = true then 'active'
        else 'pending'
      end
      where coalesce(nullif(status,''), '') = '';

    update public.djs
      set can_go_live = (status = 'active')
      where can_go_live is distinct from (status = 'active');
  end if;
end $$;
