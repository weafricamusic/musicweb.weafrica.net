-- Update DJ subscription plans with finalized tiers
-- Free, Plus (MK 4,000), and Pro (MK 7,000)

delete from subscription_plans where role = 'dj' and plan in ('free', 'plus', 'pro');
insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  -- DJ Free tier
  (
    'dj', 'free', 0, 'MWK', 'month',
    '{
      "tier": "free",
      "watch_battles": true,
      "join_as_audience": true,
      "host_battles": false,
      "receive_gifts": false,
      "can_withdraw": false,
      "limited_trial": true,
      "schedule_events": false,
      "featured_badge": false,
      "priority_listing": false
    }'::jsonb
  ),
  -- DJ Plus tier
  (
    'dj', 'plus', 4000, 'MWK', 'month',
    '{
      "tier": "plus",
      "watch_battles": true,
      "join_as_audience": true,
      "host_battles": true,
      "limited_hosting": true,
      "receive_gifts": true,
      "platform_holds_funds": true,
      "can_withdraw": false,
      "schedule_events": false,
      "featured_badge": false,
      "priority_listing": false
    }'::jsonb
  ),
  -- DJ Pro tier
  (
    'dj', 'pro', 7000, 'MWK', 'month',
    '{
      "tier": "pro",
      "watch_battles": true,
      "join_as_audience": true,
      "host_battles": true,
      "unlimited_hosting": true,
      "receive_gifts": true,
      "can_withdraw": true,
      "schedule_events": true,
      "featured_badge": true,
      "priority_listing": true
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
