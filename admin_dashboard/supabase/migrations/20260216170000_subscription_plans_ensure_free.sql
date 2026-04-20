-- Ensure the canonical Free plan exists in subscription_plans.
-- Some UIs/clients assume plan_id='free' is present in the DB catalog.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'subscription_plans'
  ) then
    raise notice 'subscription_plans table not found; skipping ensure_free migration.';
    return;
  end if;

  -- Ensure basic row exists (columns guaranteed by core migration).
  insert into public.subscription_plans (plan_id, name, price_mwk, billing_interval)
  values ('free', 'Free', 0, 'month')
  on conflict (plan_id) do update
    set name = excluded.name,
        price_mwk = excluded.price_mwk,
        billing_interval = excluded.billing_interval;

  -- Best-effort: populate optional columns when present.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'audience'
  ) then
    update public.subscription_plans
    set audience = 'consumer'
    where plan_id = 'free'
      and (audience is null or audience <> 'consumer');
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'is_active'
  ) then
    update public.subscription_plans
    set is_active = true
    where plan_id = 'free'
      and is_active is distinct from true;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'coins_multiplier'
  ) then
    update public.subscription_plans
    set coins_multiplier = 1
    where plan_id = 'free'
      and (coins_multiplier is null or coins_multiplier <> 1);
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'ads_enabled'
  ) then
    update public.subscription_plans
    set ads_enabled = true
    where plan_id = 'free'
      and ads_enabled is distinct from true;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'can_participate_battles'
  ) then
    update public.subscription_plans
    set can_participate_battles = false
    where plan_id = 'free'
      and can_participate_battles is distinct from false;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'battle_priority'
  ) then
    update public.subscription_plans
    set battle_priority = 'none'
    where plan_id = 'free'
      and (battle_priority is null or lower(trim(battle_priority)) <> 'none');
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'analytics_level'
  ) then
    update public.subscription_plans
    set analytics_level = 'basic'
    where plan_id = 'free'
      and (analytics_level is null or lower(trim(analytics_level)) <> 'basic');
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'content_access'
  ) then
    update public.subscription_plans
    set content_access = 'limited'
    where plan_id = 'free'
      and (content_access is null or lower(trim(content_access)) <> 'limited');
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'content_limit_ratio'
  ) then
    update public.subscription_plans
    set content_limit_ratio = 0.300
    where plan_id = 'free'
      and (content_limit_ratio is null or content_limit_ratio <> 0.300);
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'featured_status'
  ) then
    update public.subscription_plans
    set featured_status = false
    where plan_id = 'free'
      and featured_status is distinct from false;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'perks'
  ) then
    update public.subscription_plans
    set perks = coalesce(perks, '{}'::jsonb) || '{
      "ads": {"interstitial_every_songs": 3, "interstitial_every_videos": 2},
      "playback": {"skips": {"unlimited": false}, "background_play": false},
      "playlists": {"create": false},
      "downloads": {"enabled": false},
      "quality": {"audio": "low", "video": "low"},
      "battles": {"access": "limited", "priority": "none"},
      "exclusive_content": "none"
    }'::jsonb
    where plan_id = 'free';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'features'
  ) then
    update public.subscription_plans
    set features = coalesce(features, '{}'::jsonb) || '{
      "ads_enabled": true,
      "coins_multiplier": 1,
      "can_participate_battles": false,
      "battle_priority": "none",
      "analytics_level": "basic",
      "content_access": "limited",
      "content_limit_ratio": 0.3,
      "featured_status": false
    }'::jsonb
    where plan_id = 'free';
  end if;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
