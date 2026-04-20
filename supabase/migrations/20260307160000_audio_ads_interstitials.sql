-- Audio ads: interstitial playback support
--
-- Aligns `public.ads` with the app/Edge API expectations for audio interstitials
-- (title, audio_url, duration_seconds, etc.) while keeping compatibility with
-- existing ad-unit rows.

alter table public.ads
  add column if not exists title text;

alter table public.ads
  add column if not exists audio_url text;

alter table public.ads
  add column if not exists image_url text;

alter table public.ads
  add column if not exists advertiser text;

alter table public.ads
  add column if not exists click_url text;

alter table public.ads
  add column if not exists duration_seconds integer;

alter table public.ads
  add column if not exists is_skippable boolean not null default false;

alter table public.ads
  add column if not exists priority integer not null default 0;

alter table public.ads
  add column if not exists updated_at timestamptz default now();

-- Allow using `ads` for multiple ad backends (e.g. ad units vs audio ads).
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ads'
      and column_name = 'name'
  ) then
    alter table public.ads alter column name drop not null;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ads'
      and column_name = 'ad_unit_id'
  ) then
    alter table public.ads alter column ad_unit_id drop not null;
  end if;
end
$$;

create index if not exists ads_audio_active_idx
  on public.ads (priority desc, created_at desc)
  where is_active = true and audio_url is not null;

-- Tracking tables for audio interstitial ads (written by Edge service role).
do $$
declare
  ads_id_type text;
begin
  select format_type(attribute.atttypid, attribute.atttypmod)
  into ads_id_type
  from pg_attribute attribute
  join pg_class class on class.oid = attribute.attrelid
  join pg_namespace namespace on namespace.oid = class.relnamespace
  where namespace.nspname = 'public'
    and class.relname = 'ads'
    and attribute.attname = 'id'
    and not attribute.attisdropped;

  if ads_id_type is null then
    raise exception 'public.ads.id column is missing';
  end if;

  execute format(
    'create table if not exists public.ads_impressions (
      id bigserial primary key,
      ad_id %s not null references public.ads(id) on delete cascade,
      user_id text,
      created_at timestamptz not null default now()
    )',
    ads_id_type
  );

  execute format(
    'create table if not exists public.ads_clicks (
      id bigserial primary key,
      ad_id %s not null references public.ads(id) on delete cascade,
      user_id text,
      created_at timestamptz not null default now()
    )',
    ads_id_type
  );

  execute format(
    'create table if not exists public.ads_completions (
      id bigserial primary key,
      ad_id %s not null references public.ads(id) on delete cascade,
      user_id text,
      created_at timestamptz not null default now()
    )',
    ads_id_type
  );
end
$$;

create index if not exists ads_impressions_ad_idx
  on public.ads_impressions (ad_id, created_at desc);

create index if not exists ads_impressions_user_idx
  on public.ads_impressions (user_id, created_at desc);

create index if not exists ads_clicks_ad_idx
  on public.ads_clicks (ad_id, created_at desc);

create index if not exists ads_clicks_user_idx
  on public.ads_clicks (user_id, created_at desc);

create index if not exists ads_completions_ad_idx
  on public.ads_completions (ad_id, created_at desc);

create index if not exists ads_completions_user_idx
  on public.ads_completions (user_id, created_at desc);

alter table public.ads_impressions enable row level security;
alter table public.ads_clicks enable row level security;
alter table public.ads_completions enable row level security;
