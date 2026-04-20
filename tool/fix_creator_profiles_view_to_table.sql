-- Converts public.creator_profiles from VIEW -> TABLE for app upserts.
-- Safe to run multiple times.
--
-- Why: PostgREST upsert with on_conflict=user_id requires a real TABLE with a
-- unique constraint on user_id. VIEWs cannot have indexes and are often not
-- updatable, which can surface as HTTP 500 in the app.

create extension if not exists pgcrypto;

do $$
declare
  relkind_char "char";
begin
  select c.relkind
  into relkind_char
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'creator_profiles'
  limit 1;

  if relkind_char = 'r' then
    raise notice 'public.creator_profiles is already a TABLE. Nothing to convert.';
    return;
  end if;

  if relkind_char = 'v' then
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'creator_profiles_view_backup'
    ) then
      raise notice 'creator_profiles_view_backup already exists. Leaving current VIEW name unchanged.';
    else
      execute 'alter view public.creator_profiles rename to creator_profiles_view_backup';
      raise notice 'Renamed VIEW to public.creator_profiles_view_backup';
    end if;
  elsif relkind_char is not null then
    raise exception 'public.creator_profiles exists as unsupported relkind=%', relkind_char;
  end if;
end $$;

create table if not exists public.creator_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id text not null unique,
  role text not null check (role in ('artist', 'dj')),
  display_name text not null,
  avatar_url text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists creator_profiles_role_created_at_idx
  on public.creator_profiles (role, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_creator_profiles_updated_at on public.creator_profiles;
create trigger trg_creator_profiles_updated_at
before update on public.creator_profiles
for each row execute function public.set_updated_at();

-- Best-effort copy from backup VIEW into new TABLE.
-- Only rows with valid user_id and role in (artist, dj) are copied.
insert into public.creator_profiles (user_id, role, display_name, avatar_url, bio)
select
  nullif(trim(v.user_id::text), '') as user_id,
  case
    when lower(coalesce(v.role::text, '')) in ('artist', 'dj') then lower(v.role::text)
    else 'artist'
  end as role,
  coalesce(nullif(trim(v.display_name::text), ''), split_part(v.user_id::text, '@', 1), 'Creator') as display_name,
  nullif(trim(v.avatar_url::text), '') as avatar_url,
  nullif(trim(v.bio::text), '') as bio
from public.creator_profiles_view_backup v
where nullif(trim(v.user_id::text), '') is not null
on conflict (user_id) do update
set
  role = excluded.role,
  display_name = excluded.display_name,
  avatar_url = excluded.avatar_url,
  bio = excluded.bio,
  updated_at = now();

-- Optional verification:
-- select relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname='public' and c.relname='creator_profiles';
-- select count(*) from public.creator_profiles;
