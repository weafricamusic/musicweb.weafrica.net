-- Repair consumer Platinum entitlements to the canonical nested structure.
-- This keeps DB-backed plans aligned with the admin seed payload and Flutter's
-- dotted-path entitlement parsing.

alter table public.subscription_plans
  add column if not exists features jsonb,
  add column if not exists perks jsonb,
  add column if not exists updated_at timestamptz default now();

-- Safety cleanup: normalize legacy Platinum identifiers (e.g. vip, VIP, Platinum)
-- so checkout + entitlements resolve consistently, then delete the obsolete rows.
-- NOTE: This does NOT delete user subscription history; it only rewires references
-- to the canonical plan_id ('platinum') and removes duplicate/alias catalog rows.
do $$
begin
  -- Ensure the canonical catalog row exists (legacy DBs sometimes only had vip).
  if not exists (select 1 from public.subscription_plans where plan_id = 'platinum') then
    begin
      insert into public.subscription_plans (plan_id, name)
      select 'platinum', 'Platinum'
      where not exists (select 1 from public.subscription_plans where plan_id = 'platinum');
    exception when others then
      raise notice 'Skipping canonical platinum insert: %', sqlerrm;
    end;
  end if;

  if to_regclass('public.user_subscriptions') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'user_subscriptions'
        and column_name = 'plan_id'
    )
  then
    update public.user_subscriptions
    set plan_id = 'platinum'
    where plan_id is not null
      and lower(trim(plan_id)) in ('vip', 'vip_listener', 'platinum')
      and plan_id <> 'platinum';
  end if;

  if to_regclass('public.subscription_payments') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'subscription_payments'
        and column_name = 'plan_id'
    )
  then
    update public.subscription_payments
    set plan_id = 'platinum'
    where plan_id is not null
      and lower(trim(plan_id)) in ('vip', 'vip_listener', 'platinum')
      and plan_id <> 'platinum';
  end if;

  if to_regclass('public.subscription_promotions') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'subscription_promotions'
        and column_name = 'target_plan_id'
    )
  then
    update public.subscription_promotions
    set target_plan_id = 'platinum'
    where target_plan_id is not null
      and lower(trim(target_plan_id)) in ('vip', 'vip_listener', 'platinum')
      and target_plan_id <> 'platinum';
  end if;

  if to_regclass('public.subscription_content_access') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'subscription_content_access'
        and column_name = 'plan_id'
    )
  then
    -- Preserve the canonical row if it exists; otherwise promote the legacy row.
    if exists (select 1 from public.subscription_content_access where plan_id = 'platinum') then
      delete from public.subscription_content_access
      where plan_id is not null
        and lower(trim(plan_id)) in ('vip', 'vip_listener', 'platinum')
        and plan_id <> 'platinum';
    else
      update public.subscription_content_access
      set plan_id = 'platinum'
      where plan_id is not null
        and lower(trim(plan_id)) in ('vip', 'vip_listener', 'platinum')
        and plan_id <> 'platinum';
    end if;
  end if;
end $$;

delete from public.subscription_plans
where plan_id is not null
  and lower(trim(plan_id)) in ('vip', 'vip_listener', 'platinum')
  and plan_id <> 'platinum';

update public.subscription_plans
set
  audience = 'consumer',
  name = 'Platinum',
  price_mwk = 8500,
  billing_interval = 'month',
  currency = coalesce(currency, 'MWK'),
  sort_order = 30,
  active = true,
  is_active = true,
  ads_enabled = false,
  coins_multiplier = 3,
  can_participate_battles = true,
  battle_priority = 'priority',
  analytics_level = 'advanced',
  content_access = 'exclusive',
  content_limit_ratio = 1.0,
  featured_status = true,
  features = $json$
  {
    "ads_enabled": false,
    "coins_multiplier": 3,
    "analytics_level": "advanced",
    "live_battles": true,
    "live_battle_access": "priority",
    "priority_live_battle": "priority",
    "premium_content": true,
    "featured_status": true,
    "background_play": true,
    "video_downloads": true,
    "audio_quality": "high",
    "audio_max_kbps": 320,
    "priority_live_access": true,
    "highlighted_comments": true,
    "exclusive_content": true,
    "ads": {
      "enabled": false,
      "interstitial_every_songs": 0
    },
    "live": {
      "access": "priority",
      "can_participate": true,
      "can_create_battle": false,
      "priority": "priority",
      "priority_access": true,
      "song_requests": {
        "enabled": true
      },
      "highlighted_comments": true
    },
    "content": {
      "exclusive": true,
      "early_access": true,
      "limit_ratio": 1.0
    },
    "gifting": {
      "tier": "vip",
      "can_send": true,
      "priority_visibility": true
    },
    "quality": {
      "audio": "high",
      "audio_max_kbps": 320
    },
    "tickets": {
      "buy": {
        "enabled": true,
        "tiers": ["standard", "vip", "priority"]
      },
      "priority_booking": true,
      "redeem_bonus_coins": true
    },
    "playback": {
      "skips_per_hour": -1,
      "background_play": true
    },
    "downloads": {
      "enabled": true,
      "video_enabled": true
    },
    "analytics": {
      "level": "advanced"
    },
    "battles": {
      "enabled": true,
      "priority": "priority"
    },
    "comments": {
      "highlighted": true
    },
    "recognition": {
      "vip_badge": true
    },
    "featured": true,
    "vip": {
      "badge": true
    },
    "vip_badge": true,
    "monetization": {
      "ads_revenue": false
    },
    "content_access": "exclusive",
    "content_limit_ratio": 1.0,
    "coins": {
      "monthly_free": {
        "amount": 200
      },
      "monthly_bonus": {
        "amount": 200
      }
    },
    "monthly_bonus_coins": 200
  }
  $json$::jsonb,
  perks = $json$
  {
    "ads_enabled": false,
    "coins_multiplier": 3,
    "analytics_level": "advanced",
    "live_battles": true,
    "live_battle_access": "priority",
    "priority_live_battle": "priority",
    "premium_content": true,
    "featured_status": true,
    "background_play": true,
    "video_downloads": true,
    "audio_quality": "high",
    "audio_max_kbps": 320,
    "priority_live_access": true,
    "highlighted_comments": true,
    "exclusive_content": true,
    "ads": {
      "enabled": false,
      "interstitial_every_songs": 0
    },
    "live": {
      "access": "priority",
      "can_participate": true,
      "can_create_battle": false,
      "priority": "priority",
      "priority_access": true,
      "song_requests": {
        "enabled": true
      },
      "highlighted_comments": true
    },
    "content": {
      "exclusive": true,
      "early_access": true,
      "limit_ratio": 1.0
    },
    "gifting": {
      "tier": "vip",
      "can_send": true,
      "priority_visibility": true
    },
    "quality": {
      "audio": "high",
      "audio_max_kbps": 320
    },
    "tickets": {
      "buy": {
        "enabled": true,
        "tiers": ["standard", "vip", "priority"]
      },
      "priority_booking": true,
      "redeem_bonus_coins": true
    },
    "playback": {
      "skips_per_hour": -1,
      "background_play": true
    },
    "downloads": {
      "enabled": true,
      "video_enabled": true
    },
    "analytics": {
      "level": "advanced"
    },
    "battles": {
      "enabled": true,
      "priority": "priority"
    },
    "comments": {
      "highlighted": true
    },
    "recognition": {
      "vip_badge": true
    },
    "featured": true,
    "vip": {
      "badge": true
    },
    "vip_badge": true,
    "monetization": {
      "ads_revenue": false
    },
    "content_access": "exclusive",
    "content_limit_ratio": 1.0,
    "coins": {
      "monthly_free": {
        "amount": 200
      },
      "monthly_bonus": {
        "amount": 200
      }
    },
    "monthly_bonus_coins": 200
  }
  $json$::jsonb,
  updated_at = now()
where lower(coalesce(plan_id, '')) in ('platinum', 'vip', 'vip_listener')
  and lower(coalesce(audience, 'consumer')) = 'consumer';