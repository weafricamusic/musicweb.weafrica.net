-- Production-ready feature flags + AI usage tracking.
--
-- Goals:
-- - Ensure subscription_plans.features contains structured feature flags used by clients.
-- - Backfill starter/pro/elite (and legacy aliases) when features are empty/missing.
-- - Add ai_usage table for monthly AI quota enforcement.
-- - Provide compatibility views: public.plans and user_subscriptions_v.

create extension if not exists pgcrypto;

-- 1) Ensure `subscription_plans.features` exists.
alter table if exists public.subscription_plans
  add column if not exists features jsonb;

do $$
begin
  -- Set default + not-null only when safe.
  begin
    alter table public.subscription_plans alter column features set default '{}'::jsonb;
  exception when undefined_column then
    null;
  end;

  begin
    update public.subscription_plans set features = coalesce(features, '{}'::jsonb) where features is null;
  exception when undefined_table then
    null;
  end;
end $$;

-- 2) Backfill plan feature JSON (only when empty / missing expected keys).
--    (-1 means unlimited.)
do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'subscription_plans'
  ) then
    raise notice 'subscription_plans missing; skipping features backfill.';
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'features'
  ) then
    -- Starter / Free
    update public.subscription_plans
    set features = jsonb_build_object(
      'max_songs', 3,
      'max_videos', 2,
      'can_host_live', false,
      'ai_monthly_limit', 1,
      'ai_max_length_minutes', 1,
      'advanced_analytics', false,
      'priority_support', false,
      'homepage_feature', false
    )
    where plan_id in ('starter','free')
      and (
        features is null
        or features = '{}'::jsonb
        or not (features ? 'max_songs')
      );

    -- Pro / Premium
    update public.subscription_plans
    set features = jsonb_build_object(
      'max_songs', -1,
      'max_videos', -1,
      'can_host_live', true,
      'ai_monthly_limit', 30,
      'ai_max_length_minutes', 3,
      'advanced_analytics', true,
      'priority_support', true,
      'homepage_feature', true
    )
    where plan_id in ('pro','premium','pro_weekly','premium_weekly')
      and (
        features is null
        or features = '{}'::jsonb
        or not (features ? 'max_songs')
      );

    -- Elite / Platinum
    update public.subscription_plans
    set features = jsonb_build_object(
      'max_songs', -1,
      'max_videos', -1,
      'can_host_live', true,
      'ai_monthly_limit', -1,
      'ai_max_length_minutes', 5,
      'advanced_analytics', true,
      'priority_support', true,
      'homepage_feature', true,
      'elite_badge', true,
      'priority_ai_queue', true
    )
    where plan_id in ('elite','platinum','elite_weekly','platinum_weekly')
      and (
        features is null
        or features = '{}'::jsonb
        or not (features ? 'max_songs')
      );
  end if;
end $$;

-- 3) Compatibility view: `plans` (simple read-model over subscription_plans).
--    This avoids duplicating data while giving client code a clean "plans" surface.
create or replace view public.plans as
select
  sp.plan_id as code,
  sp.name,
  case when lower(sp.billing_interval) = 'month' then sp.price_mwk else null end as price_monthly,
  null::integer as price_yearly,
  coalesce(sp.features, '{}'::jsonb) as features,
  sp.created_at,
  sp.updated_at
from public.subscription_plans sp;

-- 4) Compatibility view: user_subscriptions with expires_at naming.
create or replace view public.user_subscriptions_v as
select
  s.id,
  s.user_id,
  s.plan_id as plan_code,
  s.started_at,
  s.ends_at as expires_at,
  s.status,
  s.country_code,
  s.source,
  s.meta,
  s.created_at,
  s.updated_at
from public.user_subscriptions s;

-- 5) AI usage (monthly).
create table if not exists public.ai_usage (
  id bigserial primary key,
  user_id text not null,
  month integer not null check (month >= 1 and month <= 12),
  year integer not null check (year >= 2020 and year <= 2100),
  songs_generated integer not null default 0 check (songs_generated >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, year, month)
);

create index if not exists ai_usage_user_month_idx on public.ai_usage (user_id, year, month);

alter table public.ai_usage enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_usage'
      and policyname = 'deny_all_ai_usage'
  ) then
    create policy deny_all_ai_usage
      on public.ai_usage
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Service-role helper to increment usage (call from trusted backend only).
create or replace function public.ai_usage_increment(
  p_user_id text,
  p_year integer,
  p_month integer,
  p_delta integer default 1
)
returns table (
  user_id text,
  year integer,
  month integer,
  songs_generated integer
)
language plpgsql
security definer
as $$
declare
  v_delta integer;
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'p_user_id required';
  end if;
  if p_year is null or p_year < 2020 or p_year > 2100 then
    raise exception 'p_year out of range';
  end if;
  if p_month is null or p_month < 1 or p_month > 12 then
    raise exception 'p_month out of range';
  end if;

  v_delta := coalesce(p_delta, 1);
  if v_delta <= 0 then
    raise exception 'p_delta must be positive';
  end if;

  insert into public.ai_usage (user_id, year, month, songs_generated)
  values (trim(p_user_id), p_year, p_month, v_delta)
  on conflict (user_id, year, month)
  do update set
    songs_generated = public.ai_usage.songs_generated + excluded.songs_generated,
    updated_at = now();

  return query
    select a.user_id, a.year, a.month, a.songs_generated
    from public.ai_usage a
    where a.user_id = trim(p_user_id)
      and a.year = p_year
      and a.month = p_month
    limit 1;
end;
$$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
