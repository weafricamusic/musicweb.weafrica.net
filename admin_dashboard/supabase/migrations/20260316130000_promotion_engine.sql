-- Promotion Engine (Admin + Paid + Analytics)
--
-- Adds the new promotion model required by Ads & Promotions:
-- - promotions (admin-controlled + approved paid promotions)
-- - paid_promotions (creator submitted, admin approved/rejected)
-- - promotion_events (views/clicks/engagement telemetry)

create extension if not exists pgcrypto;

-- 1) Promotions table (upgrade-safe)
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),

  -- New required promotion fields
  promotion_type text,
  target_id text,
  country text,
  surface text,
  start_date timestamptz,
  end_date timestamptz,
  status text not null default 'draft',
  created_by text,

  -- Existing/compat fields used by older endpoints
  title text not null default 'Promotion',
  description text,
  banner_url text,
  image_url text not null default '',
  source_type text not null default 'admin',
  budget_coins integer,
  audience text,
  target_plan text not null default 'all',
  is_active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.promotions
  add column if not exists promotion_type text,
  add column if not exists target_id text,
  add column if not exists country text,
  add column if not exists surface text,
  add column if not exists start_date timestamptz,
  add column if not exists end_date timestamptz,
  add column if not exists status text,
  add column if not exists created_by text,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists banner_url text,
  add column if not exists image_url text,
  add column if not exists source_type text,
  add column if not exists budget_coins integer,
  add column if not exists audience text,
  add column if not exists target_plan text,
  add column if not exists is_active boolean,
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- Safe defaults for existing rows
update public.promotions
set
  title = coalesce(nullif(title, ''), 'Promotion'),
  image_url = coalesce(image_url, ''),
  source_type = coalesce(nullif(source_type, ''), 'admin'),
  target_plan = coalesce(nullif(target_plan, ''), 'all'),
  is_active = coalesce(is_active, false),
  status = coalesce(
    nullif(status, ''),
    case when coalesce(is_active, false) then 'active' else 'draft' end
  ),
  country = coalesce(nullif(country, ''), 'MW'),
  start_date = coalesce(start_date, starts_at),
  end_date = coalesce(end_date, ends_at),
  banner_url = coalesce(nullif(banner_url, ''), nullif(image_url, '')),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now());

alter table public.promotions
  alter column title set default 'Promotion',
  alter column title set not null,
  alter column image_url set default '',
  alter column image_url set not null,
  alter column source_type set default 'admin',
  alter column source_type set not null,
  alter column target_plan set default 'all',
  alter column target_plan set not null,
  alter column is_active set default false,
  alter column is_active set not null,
  alter column status set default 'draft',
  alter column status set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'promotions_promotion_type_check'
  ) then
    alter table public.promotions
      add constraint promotions_promotion_type_check
      check (promotion_type is null or promotion_type in ('artist','dj','battle','event','ride'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'promotions_surface_check'
  ) then
    alter table public.promotions
      add constraint promotions_surface_check
      check (surface is null or surface in ('home_banner','discover','feed','live_battle','events'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'promotions_status_check_v2'
  ) then
    alter table public.promotions
      add constraint promotions_status_check_v2
      check (status in ('draft','scheduled','active','paused','ended','rejected'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'promotions_source_type_check'
  ) then
    alter table public.promotions
      add constraint promotions_source_type_check
      check (source_type in ('admin','paid'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'promotions_budget_coins_non_negative'
  ) then
    alter table public.promotions
      add constraint promotions_budget_coins_non_negative
      check (budget_coins is null or budget_coins >= 0);
  end if;
end $$;

create index if not exists promotions_country_idx on public.promotions (country);
create index if not exists promotions_surface_idx on public.promotions (surface);
create index if not exists promotions_status_idx on public.promotions (status);
create index if not exists promotions_source_type_idx on public.promotions (source_type);
create index if not exists promotions_start_date_idx on public.promotions (start_date desc);
create index if not exists promotions_end_date_idx on public.promotions (end_date desc);
create index if not exists promotions_promotion_type_idx on public.promotions (promotion_type);
create index if not exists promotions_target_id_idx on public.promotions (target_id);

-- 2) Paid promotions queue
create table if not exists public.paid_promotions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  content_id text not null,
  content_type text not null default 'song',
  coins integer not null,
  duration integer not null,
  country text not null,
  audience text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  review_note text,
  starts_at timestamptz,
  ends_at timestamptz,
  promotion_id uuid references public.promotions(id) on delete set null,

  constraint paid_promotions_coins_positive check (coins > 0),
  constraint paid_promotions_duration_positive check (duration > 0),
  constraint paid_promotions_status_check check (status in ('pending','approved','rejected','active','completed','cancelled'))
);

create index if not exists paid_promotions_user_id_idx on public.paid_promotions (user_id);
create index if not exists paid_promotions_status_idx on public.paid_promotions (status);
create index if not exists paid_promotions_country_idx on public.paid_promotions (country);
create index if not exists paid_promotions_created_at_idx on public.paid_promotions (created_at desc);
create index if not exists paid_promotions_content_idx on public.paid_promotions (content_type, content_id);
create index if not exists paid_promotions_promotion_id_idx on public.paid_promotions (promotion_id);

-- 3) Promotion analytics events (views/clicks/engagement)
create table if not exists public.promotion_events (
  id bigserial primary key,
  promotion_id uuid references public.promotions(id) on delete cascade,
  paid_promotion_id uuid references public.paid_promotions(id) on delete set null,
  event_type text not null,
  country text,
  surface text,
  actor_id text,
  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb,

  constraint promotion_events_event_type_check check (event_type in ('view','click','engagement'))
);

create index if not exists promotion_events_promotion_idx on public.promotion_events (promotion_id, created_at desc);
create index if not exists promotion_events_paid_promotion_idx on public.promotion_events (paid_promotion_id, created_at desc);
create index if not exists promotion_events_country_idx on public.promotion_events (country, created_at desc);
create index if not exists promotion_events_event_type_idx on public.promotion_events (event_type, created_at desc);
create index if not exists promotion_events_surface_idx on public.promotion_events (surface, created_at desc);

-- Shared updated_at trigger helper
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'promotions_set_updated_at') then
    create trigger promotions_set_updated_at
      before update on public.promotions
      for each row
      execute function public.tg_set_updated_at();
  end if;

  if not exists (select 1 from pg_trigger where tgname = 'paid_promotions_set_updated_at') then
    create trigger paid_promotions_set_updated_at
      before update on public.paid_promotions
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

-- RLS deny-all; admin routes use service_role key.
alter table public.promotions enable row level security;
alter table public.paid_promotions enable row level security;
alter table public.promotion_events enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'promotions' and policyname = 'deny_all_promotions'
  ) then
    create policy deny_all_promotions
      on public.promotions
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'paid_promotions' and policyname = 'deny_all_paid_promotions'
  ) then
    create policy deny_all_paid_promotions
      on public.paid_promotions
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'promotion_events' and policyname = 'deny_all_promotion_events'
  ) then
    create policy deny_all_promotion_events
      on public.promotion_events
      for all
      using (false)
      with check (false);
  end if;
end $$;

notify pgrst, 'reload schema';
