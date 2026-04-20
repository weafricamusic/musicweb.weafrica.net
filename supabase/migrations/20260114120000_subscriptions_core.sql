-- Subscriptions core tables for WeAfrica plans + user subscription state.
-- Service-role bypasses RLS; normal clients are denied by default.

create extension if not exists pgcrypto;
-- 1) Canonical plan catalog (seeded)
create table if not exists public.subscription_plans (
  plan_id text primary key check (plan_id in ('free','premium','platinum')),
  name text not null,
  price_mwk integer not null default 0 check (price_mwk >= 0),
  billing_interval text not null default 'month' check (billing_interval in ('month')),

  -- Core entitlements
  coins_multiplier integer not null default 1 check (coins_multiplier >= 1),
  ads_enabled boolean not null default true,
  can_participate_battles boolean not null default false,
  battle_priority text not null default 'none' check (battle_priority in ('none','standard','priority')),
  analytics_level text not null default 'basic' check (analytics_level in ('basic','standard','advanced')),

  -- Content access
  content_access text not null default 'limited' check (content_access in ('limited','standard','exclusive')),
  content_limit_ratio numeric(4,3) check (content_limit_ratio is null or (content_limit_ratio >= 0 and content_limit_ratio <= 1)),

  -- Premium perks
  featured_status boolean not null default false,
  perks jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- If the table already exists from an older schema, ensure required columns exist.
-- (Supabase SQL runner executes statements sequentially; this prevents seed failures.)
alter table public.subscription_plans
  add column if not exists plan_id text,
  add column if not exists name text,
  add column if not exists price_mwk integer,
  add column if not exists billing_interval text,
  add column if not exists coins_multiplier integer,
  add column if not exists ads_enabled boolean,
  add column if not exists can_participate_battles boolean,
  add column if not exists battle_priority text,
  add column if not exists analytics_level text,
  add column if not exists content_access text,
  add column if not exists content_limit_ratio numeric(4,3),
  add column if not exists featured_status boolean,
  add column if not exists perks jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;
-- Backfill plan_id for legacy rows when possible.
do $$
declare
  has_id boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'id'
  ) into has_id;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'name'
  ) then
    -- Safe backfill: avoid violating existing unique constraints on plan_id.
    -- If multiple legacy rows would map to the same plan_id, pick only one.
    -- If the target plan_id already exists, skip assignment.
    if has_id then
      with candidates as (
        select
          id,
          case
            when lower(trim(name)) = 'free' then 'free'
            when lower(trim(name)) = 'premium' then 'premium'
            when lower(trim(name)) = 'platinum' then 'platinum'
            else null
          end as desired_plan_id
        from public.subscription_plans
        where plan_id is null
      ), ranked as (
        select
          id,
          desired_plan_id,
          row_number() over (partition by desired_plan_id order by id asc) as rn
        from candidates
        where desired_plan_id is not null
      )
      update public.subscription_plans sp
        set plan_id = r.desired_plan_id
      from ranked r
      where sp.id = r.id
        and r.rn = 1
        and not exists (
          select 1
          from public.subscription_plans sp2
          where sp2.plan_id = r.desired_plan_id
        );
    else
      with candidates as (
        select
          ctid as row_ctid,
          case
            when lower(trim(name)) = 'free' then 'free'
            when lower(trim(name)) = 'premium' then 'premium'
            when lower(trim(name)) = 'platinum' then 'platinum'
            else null
          end as desired_plan_id
        from public.subscription_plans
        where plan_id is null
      ), ranked as (
        select
          row_ctid,
          desired_plan_id,
          row_number() over (partition by desired_plan_id order by row_ctid) as rn
        from candidates
        where desired_plan_id is not null
      )
      update public.subscription_plans sp
        set plan_id = r.desired_plan_id
      from ranked r
      where sp.ctid = r.row_ctid
        and r.rn = 1
        and not exists (
          select 1
          from public.subscription_plans sp2
          where sp2.plan_id = r.desired_plan_id
        );
    end if;
  end if;

  -- Legacy schema: `plan` is the canonical identifier.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'plan'
  ) then
    -- Safe backfill from legacy `plan` column.
    if has_id then
      with candidates as (
        select
          id,
          case
            when lower(trim(plan)) = 'free' then 'free'
            when lower(trim(plan)) = 'premium' then 'premium'
            when lower(trim(plan)) = 'platinum' then 'platinum'
            else null
          end as desired_plan_id
        from public.subscription_plans
        where plan_id is null
      ), ranked as (
        select
          id,
          desired_plan_id,
          row_number() over (partition by desired_plan_id order by id asc) as rn
        from candidates
        where desired_plan_id is not null
      )
      update public.subscription_plans sp
        set plan_id = r.desired_plan_id
      from ranked r
      where sp.id = r.id
        and r.rn = 1
        and not exists (
          select 1
          from public.subscription_plans sp2
          where sp2.plan_id = r.desired_plan_id
        );
    else
      with candidates as (
        select
          ctid as row_ctid,
          case
            when lower(trim(plan)) = 'free' then 'free'
            when lower(trim(plan)) = 'premium' then 'premium'
            when lower(trim(plan)) = 'platinum' then 'platinum'
            else null
          end as desired_plan_id
        from public.subscription_plans
        where plan_id is null
      ), ranked as (
        select
          row_ctid,
          desired_plan_id,
          row_number() over (partition by desired_plan_id order by row_ctid) as rn
        from candidates
        where desired_plan_id is not null
      )
      update public.subscription_plans sp
        set plan_id = r.desired_plan_id
      from ranked r
      where sp.ctid = r.row_ctid
        and r.rn = 1
        and not exists (
          select 1
          from public.subscription_plans sp2
          where sp2.plan_id = r.desired_plan_id
        );
    end if;
  end if;
end $$;
-- Ensure plan_id can be used for UPSERT + foreign keys.
-- If legacy data already contains duplicates (multiple rows per plan), keep the oldest row as canonical
-- and null out plan_id on the duplicates (unique indexes allow multiple NULLs).
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'id'
  ) then
    with ranked as (
      select
        id,
        plan_id,
        row_number() over (partition by plan_id order by id asc) as rn
      from public.subscription_plans
      where plan_id is not null
    )
    update public.subscription_plans sp
      set plan_id = null
    from ranked r
    where sp.id = r.id
      and r.rn > 1;
  end if;
end $$;
create unique index if not exists subscription_plans_plan_id_unique on public.subscription_plans (plan_id);
alter table public.subscription_plans enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_plans'
      and policyname = 'deny_all_subscription_plans'
  ) then
    create policy deny_all_subscription_plans
      on public.subscription_plans
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- Seed plans (idempotent).
-- Some existing deployments may already have a legacy `subscription_plans` table with extra NOT NULL columns
-- (e.g. `role`). We detect those columns and include them in the seed insert.
do $$
declare
  has_role boolean;
  has_plan boolean;
  has_price boolean;
  has_currency boolean;
  has_features boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'role'
  ) into has_role;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'plan'
  ) into has_plan;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'price'
  ) into has_price;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'currency'
  ) into has_currency;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'features'
  ) into has_features;

  -- Legacy schema (your DB): role + plan are required.
  if has_role and has_plan then
    execute $sql$
      insert into public.subscription_plans (
        plan_id,
        name,
        price_mwk,
        billing_interval,
        coins_multiplier,
        ads_enabled,
        can_participate_battles,
        battle_priority,
        analytics_level,
        content_access,
        content_limit_ratio,
        featured_status,
        perks,
        role,
        plan,
        price,
        currency,
        features
      )
      values
        (
          'free',
          'Free',
          0,
          'month',
          1,
          true,
          false,
          'none',
          'basic',
          'limited',
          0.300,
          false,
          '{"live_stream_access":"limited","exclusive_content":"none"}'::jsonb,
          'free',
          'free',
          0,
          'MWK',
          '{"ads_enabled":true,"coins_multiplier":1,"can_participate_battles":false,"battle_priority":"none","analytics_level":"basic","content_access":"limited","content_limit_ratio":0.3,"featured_status":false,"perks":{"live_stream_access":"limited","exclusive_content":"none"}}'::jsonb
        ),
        (
          'premium',
          'Premium',
          2000,
          'month',
          2,
          false,
          true,
          'standard',
          'standard',
          'standard',
          null,
          false,
          '{"exclusive_content":"limited"}'::jsonb,
          'premium',
          'premium',
          2000,
          'MWK',
          '{"ads_enabled":false,"coins_multiplier":2,"can_participate_battles":true,"battle_priority":"standard","analytics_level":"standard","content_access":"standard","featured_status":false,"perks":{"exclusive_content":"limited"}}'::jsonb
        ),
        (
          'platinum',
          'Platinum',
          5000,
          'month',
          3,
          false,
          true,
          'priority',
          'advanced',
          'exclusive',
          null,
          true,
          '{"exclusive_content":"full","exclusive_notifications":true,"featured_status":true}'::jsonb,
          'platinum',
          'platinum',
          5000,
          'MWK',
          '{"ads_enabled":false,"coins_multiplier":3,"can_participate_battles":true,"battle_priority":"priority","analytics_level":"advanced","content_access":"exclusive","featured_status":true,"perks":{"exclusive_content":"full","exclusive_notifications":true,"featured_status":true}}'::jsonb
        )
      on conflict (plan_id) do update set
        name = excluded.name,
        price_mwk = excluded.price_mwk,
        billing_interval = excluded.billing_interval,
        coins_multiplier = excluded.coins_multiplier,
        ads_enabled = excluded.ads_enabled,
        can_participate_battles = excluded.can_participate_battles,
        battle_priority = excluded.battle_priority,
        analytics_level = excluded.analytics_level,
        content_access = excluded.content_access,
        content_limit_ratio = excluded.content_limit_ratio,
        featured_status = excluded.featured_status,
        perks = excluded.perks,
        role = excluded.role,
        plan = excluded.plan,
        price = excluded.price,
        currency = excluded.currency,
        features = excluded.features,
        updated_at = now();
    $sql$;
  else
    -- Modern schema only.
    execute $sql$
      insert into public.subscription_plans (
        plan_id,
        name,
        price_mwk,
        billing_interval,
        coins_multiplier,
        ads_enabled,
        can_participate_battles,
        battle_priority,
        analytics_level,
        content_access,
        content_limit_ratio,
        featured_status,
        perks
      )
      values
        (
          'free',
          'Free',
          0,
          'month',
          1,
          true,
          false,
          'none',
          'basic',
          'limited',
          0.300,
          false,
          '{"live_stream_access":"limited","exclusive_content":"none"}'::jsonb
        ),
        (
          'premium',
          'Premium',
          2000,
          'month',
          2,
          false,
          true,
          'standard',
          'standard',
          'standard',
          null,
          false,
          '{"exclusive_content":"limited"}'::jsonb
        ),
        (
          'platinum',
          'Platinum',
          5000,
          'month',
          3,
          false,
          true,
          'priority',
          'advanced',
          'exclusive',
          null,
          true,
          '{"exclusive_content":"full","exclusive_notifications":true,"featured_status":true}'::jsonb
        )
      on conflict (plan_id) do update set
        name = excluded.name,
        price_mwk = excluded.price_mwk,
        billing_interval = excluded.billing_interval,
        coins_multiplier = excluded.coins_multiplier,
        ads_enabled = excluded.ads_enabled,
        can_participate_battles = excluded.can_participate_battles,
        battle_priority = excluded.battle_priority,
        analytics_level = excluded.analytics_level,
        content_access = excluded.content_access,
        content_limit_ratio = excluded.content_limit_ratio,
        featured_status = excluded.featured_status,
        perks = excluded.perks,
        updated_at = now();
    $sql$;
  end if;
end $$;
-- 2) User subscription state (append-only; inactivate via status changes)
create table if not exists public.user_subscriptions (
  id bigserial primary key,
  user_id text not null,
  plan_id text not null references public.subscription_plans (plan_id),
  status text not null default 'active' check (status in ('active','canceled','expired','replaced')),
  started_at timestamptz not null default now(),
  ends_at timestamptz,
  auto_renew boolean not null default true,
  country_code text not null default 'MW',
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);
create index if not exists user_subscriptions_user_idx on public.user_subscriptions (user_id);
create index if not exists user_subscriptions_status_idx on public.user_subscriptions (status);
create index if not exists user_subscriptions_plan_idx on public.user_subscriptions (plan_id);
create index if not exists user_subscriptions_ends_at_idx on public.user_subscriptions (ends_at);
create index if not exists user_subscriptions_created_at_idx on public.user_subscriptions (created_at desc);
-- Prevent multiple concurrently-active subscriptions per user.
create unique index if not exists user_subscriptions_one_active_idx
  on public.user_subscriptions (user_id)
  where status = 'active';
alter table public.user_subscriptions enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_subscriptions'
      and policyname = 'deny_all_user_subscriptions'
  ) then
    create policy deny_all_user_subscriptions
      on public.user_subscriptions
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 3) Helper RPC: active subscription counts by plan (for admin dashboard)
create or replace function public.subscription_plan_counts(p_country_code text default null)
returns table (
  plan_id text,
  active_count bigint
)
language sql
stable
as $$
  select s.plan_id, count(*)::bigint as active_count
  from public.user_subscriptions s
  where s.status = 'active'
    and (p_country_code is null or s.country_code = p_country_code)
  group by s.plan_id
  order by s.plan_id
$$;
