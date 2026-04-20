create extension if not exists pgcrypto;

create table if not exists public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  campaign_type text not null,
  format text not null,
  surface text not null,
  title text not null,
  description text,
  sponsor_name text,
  asset_url text,
  video_url text,
  cta_label text,
  cta_url text,
  audience text,
  target_type text,
  target_ref_id text,
  starts_at timestamptz,
  ends_at timestamptz,
  frequency_cap_daily integer not null default 0,
  priority integer not null default 0,
  status text not null default 'draft',
  approval_status text not null default 'pending',
  is_enabled boolean not null default false,
  created_by text,
  approved_by text,
  approved_at timestamptz,
  rejection_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ad_campaigns_country_code_check check (country_code ~ '^[A-Z]{2}$'),
  constraint ad_campaigns_campaign_type_check check (campaign_type in ('admob','direct_brand','in_app_promo')),
  constraint ad_campaigns_format_check check (format in ('banner','video','interstitial','native','audio','promo_card')),
  constraint ad_campaigns_surface_check check (surface in ('home_banner','discover','feed','live_battle','events','ride','audio_interstitial')),
  constraint ad_campaigns_status_check check (status in ('draft','scheduled','active','paused','completed','cancelled')),
  constraint ad_campaigns_approval_status_check check (approval_status in ('pending','approved','rejected')),
  constraint ad_campaigns_frequency_cap_daily_check check (frequency_cap_daily >= 0),
  constraint ad_campaigns_schedule_check check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists ad_campaigns_country_code_idx on public.ad_campaigns (country_code);
create index if not exists ad_campaigns_campaign_type_idx on public.ad_campaigns (campaign_type);
create index if not exists ad_campaigns_surface_idx on public.ad_campaigns (surface);
create index if not exists ad_campaigns_status_idx on public.ad_campaigns (status);
create index if not exists ad_campaigns_approval_status_idx on public.ad_campaigns (approval_status);
create index if not exists ad_campaigns_enabled_priority_idx on public.ad_campaigns (country_code, is_enabled, priority desc, starts_at desc);
create index if not exists ad_campaigns_schedule_idx on public.ad_campaigns (starts_at, ends_at);

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
  if not exists (select 1 from pg_trigger where tgname = 'ad_campaigns_set_updated_at') then
    create trigger ad_campaigns_set_updated_at
      before update on public.ad_campaigns
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

alter table public.ad_campaigns enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ad_campaigns'
      and policyname = 'deny_all_ad_campaigns'
  ) then
    create policy deny_all_ad_campaigns
      on public.ad_campaigns
      for all
      using (false)
      with check (false);
  end if;
end $$;

notify pgrst, 'reload schema';