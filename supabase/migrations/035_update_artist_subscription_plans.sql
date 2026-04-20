-- Update subscription plans for Artist (Free/Pro/Premium) with monthly + yearly pricing
-- and allow multiple billing intervals per plan.

-- Previous schema enforced unique (role, plan). We need (role, plan, billing_interval)
-- to support monthly + yearly prices.

drop index if exists idx_subscription_plans_role_plan;
create unique index if not exists idx_subscription_plans_role_plan_interval
on subscription_plans(role, plan, billing_interval);
-- Seed / update Artist plans (idempotent)
-- Pricing (MWK): Pro 7,500/month or 75,000/year; Premium 15,000/month or 150,000/year

insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  (
    'artist','free',0,'MWK','month',
    '{
      "max_songs": 5,
      "max_short_videos": 3,
      "basic_profile": true,
      "search_reach": "limited",
      "analytics_level": "basic",
      "analytics": ["total_plays","likes"],
      "live_battles": "limited",
      "events": "approval_required",
      "monetization": false,
      "advanced_analytics": false,
      "ads_on_content": true,
      "badge": "FREE"
    }'::jsonb
  ),
  (
    'artist','free',0,'MWK','year',
    '{
      "max_songs": 5,
      "max_short_videos": 3,
      "basic_profile": true,
      "search_reach": "limited",
      "analytics_level": "basic",
      "analytics": ["total_plays","likes"],
      "live_battles": "limited",
      "events": "approval_required",
      "monetization": false,
      "advanced_analytics": false,
      "ads_on_content": true,
      "badge": "FREE"
    }'::jsonb
  ),
  (
    'artist','pro',7500,'MWK','month',
    '{
      "max_songs": 50,
      "max_short_videos": "unlimited",
      "monetization": true,
      "monetization_features": ["gifts","coins","sell_event_tickets"],
      "live_battles": "join_and_host",
      "analytics_level": "mid",
      "analytics": ["plays_by_country","follower_growth"],
      "priority_content_review": true,
      "ads_on_content": "reduced",
      "homepage_promotion": false,
      "verified_badge": false,
      "badge": "PRO"
    }'::jsonb
  ),
  (
    'artist','pro',75000,'MWK','year',
    '{
      "max_songs": 50,
      "max_short_videos": "unlimited",
      "monetization": true,
      "monetization_features": ["gifts","coins","sell_event_tickets"],
      "live_battles": "join_and_host",
      "analytics_level": "mid",
      "analytics": ["plays_by_country","follower_growth"],
      "priority_content_review": true,
      "ads_on_content": "reduced",
      "homepage_promotion": false,
      "verified_badge": false,
      "badge": "PRO"
    }'::jsonb
  ),
  (
    'artist','premium',15000,'MWK','month',
    '{
      "max_songs": "unlimited",
      "max_short_videos": "unlimited",
      "monetization": true,
      "monetization_features": ["gifts","coins","sell_event_tickets"],
      "homepage_promotion": true,
      "featured_placement": true,
      "analytics_level": "advanced",
      "analytics": ["revenue","watch_time","audience_demographics"],
      "verified_badge": true,
      "priority_support": true,
      "ads_on_content": false,
      "early_access": true,
      "badge": "PREMIUM"
    }'::jsonb
  ),
  (
    'artist','premium',150000,'MWK','year',
    '{
      "max_songs": "unlimited",
      "max_short_videos": "unlimited",
      "monetization": true,
      "monetization_features": ["gifts","coins","sell_event_tickets"],
      "homepage_promotion": true,
      "featured_placement": true,
      "analytics_level": "advanced",
      "analytics": ["revenue","watch_time","audience_demographics"],
      "verified_badge": true,
      "priority_support": true,
      "ads_on_content": false,
      "early_access": true,
      "badge": "PREMIUM"
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
