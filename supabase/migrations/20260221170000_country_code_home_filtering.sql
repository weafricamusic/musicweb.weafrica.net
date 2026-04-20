-- Add country_code columns to support Malawi-first auto-country filtering.
-- Safe to run multiple times.

do $$
begin
  -- profiles
  if to_regclass('public.profiles') is not null then
    alter table public.profiles add column if not exists country_code text;
    update public.profiles set country_code = 'MW' where country_code is null;
    create index if not exists profiles_country_code_idx on public.profiles (country_code);
  end if;

  -- songs
  if to_regclass('public.songs') is not null then
    alter table public.songs add column if not exists country_code text;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public' and table_name = 'songs' and column_name = 'country'
    ) then
      execute 'update public.songs set country_code = coalesce(country_code, country) where country_code is null and country is not null';
    end if;

    update public.songs set country_code = 'MW' where country_code is null;
    create index if not exists songs_country_code_created_at_idx on public.songs (country_code, created_at desc);
  end if;

  -- albums
  if to_regclass('public.albums') is not null then
    alter table public.albums add column if not exists country_code text;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public' and table_name = 'albums' and column_name = 'country'
    ) then
      execute 'update public.albums set country_code = coalesce(country_code, country) where country_code is null and country is not null';
    end if;

    update public.albums set country_code = 'MW' where country_code is null;
    create index if not exists albums_country_code_published_at_idx on public.albums (country_code, published_at desc);
  end if;

  -- videos
  if to_regclass('public.videos') is not null then
    alter table public.videos add column if not exists country_code text;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public' and table_name = 'videos' and column_name = 'country'
    ) then
      execute 'update public.videos set country_code = coalesce(country_code, country) where country_code is null and country is not null';
    end if;

    update public.videos set country_code = 'MW' where country_code is null;
    create index if not exists videos_country_code_created_at_idx on public.videos (country_code, created_at desc);
  end if;

  -- battle_invites (best-effort metadata)
  if to_regclass('public.battle_invites') is not null then
    alter table public.battle_invites add column if not exists country_code text;
    update public.battle_invites set country_code = 'MW' where country_code is null;
    create index if not exists battle_invites_country_code_created_at_idx on public.battle_invites (country_code, created_at desc);
  end if;
end $$;
