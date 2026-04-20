-- Align subscription_plans with artist tier taxonomy: starter/pro/elite.
-- Keep legacy IDs (free/premium/platinum) valid for backward compatibility.

create extension if not exists pgcrypto;

do $$
declare
  plan_id_constraint_name text;
  has_role boolean := false;
  has_plan boolean := false;
  has_price boolean := false;
  has_currency boolean := false;
  has_features_col boolean := false;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'subscription_plans'
  ) then
    raise notice 'subscription_plans table not found; skipping artist tier alignment.';
    return;
  end if;

  -- Drop old restrictive check if present so new IDs can be stored.
  select tc.constraint_name
  into plan_id_constraint_name
  from information_schema.table_constraints tc
  join information_schema.constraint_column_usage ccu
    on ccu.constraint_schema = tc.constraint_schema
   and ccu.constraint_name = tc.constraint_name
  where tc.table_schema = 'public'
    and tc.table_name = 'subscription_plans'
    and tc.constraint_type = 'CHECK'
    and ccu.column_name = 'plan_id'
  order by tc.constraint_name
  limit 1;

  if plan_id_constraint_name is not null then
    execute format('alter table public.subscription_plans drop constraint if exists %I', plan_id_constraint_name);
  end if;

  -- Canonical + legacy-safe IDs.
  begin
    alter table public.subscription_plans
      add constraint subscription_plans_plan_id_check
      check (
        plan_id in (
          'starter','pro','elite',
          'free','premium','platinum',
          'pro_weekly','elite_weekly','premium_weekly','platinum_weekly'
        )
      );
  exception when duplicate_object then
    null;
  end;

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
  ) into has_features_col;

  if has_role then
    update public.subscription_plans
    set role = case
      when plan_id in ('starter', 'free') then 'free'
      when plan_id in ('pro', 'pro_weekly', 'premium', 'premium_weekly') then 'premium'
      when plan_id in ('elite', 'elite_weekly', 'platinum', 'platinum_weekly') then 'platinum'
      else coalesce(role, 'free')
    end
    where role is null;
  end if;

  if has_plan then
    update public.subscription_plans
    set plan = case
      when plan_id in ('starter', 'free') then 'free'
      when plan_id in ('pro', 'pro_weekly', 'premium', 'premium_weekly') then 'premium'
      when plan_id in ('elite', 'elite_weekly', 'platinum', 'platinum_weekly') then 'platinum'
      else coalesce(plan, 'free')
    end
    where plan is null;
  end if;

  if has_price then
    update public.subscription_plans
    set price = coalesce(price, price_mwk, 0)
    where price is null;
  end if;

  if has_currency then
    update public.subscription_plans
    set currency = coalesce(currency, 'MWK')
    where currency is null;
  end if;

  if has_features_col then
    update public.subscription_plans
    set features = coalesce(features, '{}'::jsonb)
    where features is null;
  end if;

  -- Seed canonical rows (idempotent). Prices default to legacy equivalents if present.
  if has_role and has_plan and has_price and has_currency and has_features_col then
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
        'starter',
        'Starter',
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
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 3, 'videos', 2),
          'live_host', false,
          'ai_music', jsonb_build_object('songs_per_month', 1, 'demo', true, 'max_minutes', 1, 'monetizable', false)
        ),
        'starter',
        'starter',
        0,
        'MWK',
        jsonb_build_object('commission_pct', 0, 'artist_plan', true, 'tier', 'starter')
      ),
      (
        'pro',
        'Pro Artist',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'premium' limit 1), 5000),
        'month',
        2,
        false,
        true,
        'standard',
        'standard',
        'standard',
        null,
        false,
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 'unlimited', 'videos', 'unlimited'),
          'live_host', true,
          'ai_music', jsonb_build_object('songs_per_month', 30, 'max_minutes', 3, 'monetizable', true),
          'billing', jsonb_build_object('monthly', true, 'yearly_discounted', true)
        ),
        'pro',
        'pro',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'premium' limit 1), 5000),
        'MWK',
        jsonb_build_object('commission_pct', 0, 'artist_plan', true, 'tier', 'pro')
      ),
      (
        'elite',
        'Elite Artist',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'platinum' limit 1), 8500),
        'month',
        3,
        false,
        true,
        'priority',
        'advanced',
        'exclusive',
        null,
        true,
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 'unlimited', 'videos', 'unlimited'),
          'live_host', true,
          'ai_music', jsonb_build_object('songs_per_month', 'unlimited', 'max_minutes', 5, 'priority_generation', true, 'monetizable', true),
          'visibility', jsonb_build_object('homepage_feature', true, 'elite_badge', true),
          'billing', jsonb_build_object('monthly', true, 'yearly_discounted', true)
        ),
        'elite',
        'elite',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'platinum' limit 1), 8500),
        'MWK',
        jsonb_build_object('commission_pct', 0, 'artist_plan', true, 'tier', 'elite')
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
  else
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
        'starter',
        'Starter',
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
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 3, 'videos', 2),
          'live_host', false,
          'ai_music', jsonb_build_object('songs_per_month', 1, 'demo', true, 'max_minutes', 1, 'monetizable', false)
        )
      ),
      (
        'pro',
        'Pro Artist',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'premium' limit 1), 5000),
        'month',
        2,
        false,
        true,
        'standard',
        'standard',
        'standard',
        null,
        false,
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 'unlimited', 'videos', 'unlimited'),
          'live_host', true,
          'ai_music', jsonb_build_object('songs_per_month', 30, 'max_minutes', 3, 'monetizable', true),
          'billing', jsonb_build_object('monthly', true, 'yearly_discounted', true)
        )
      ),
      (
        'elite',
        'Elite Artist',
        coalesce((select price_mwk from public.subscription_plans where plan_id = 'platinum' limit 1), 8500),
        'month',
        3,
        false,
        true,
        'priority',
        'advanced',
        'exclusive',
        null,
        true,
        jsonb_build_object(
          'commission_pct', 0,
          'artist_plan', true,
          'upload_limits', jsonb_build_object('songs', 'unlimited', 'videos', 'unlimited'),
          'live_host', true,
          'ai_music', jsonb_build_object('songs_per_month', 'unlimited', 'max_minutes', 5, 'priority_generation', true, 'monetizable', true),
          'visibility', jsonb_build_object('homepage_feature', true, 'elite_badge', true),
          'billing', jsonb_build_object('monthly', true, 'yearly_discounted', true)
        )
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
  end if;

  -- Normalize active subscriptions to canonical IDs.
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'user_subscriptions'
  ) then
    update public.user_subscriptions
    set plan_id = case
      when plan_id = 'free' then 'starter'
      when plan_id = 'premium' then 'pro'
      when plan_id = 'platinum' then 'elite'
      when plan_id = 'premium_weekly' then 'pro_weekly'
      when plan_id = 'platinum_weekly' then 'elite_weekly'
      else plan_id
    end,
    updated_at = now()
    where plan_id in ('free','premium','platinum','premium_weekly','platinum_weekly');
  end if;
end $$;

notify pgrst, 'reload schema';
