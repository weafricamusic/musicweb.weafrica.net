-- Update artist subscription plans with finalized tiers
-- Free, Plus (MK 3,000), and Pro (MK 6,000)

delete from subscription_plans where role = 'artist' and plan in ('free', 'plus', 'pro');
insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  -- Artist Free tier
  (
    'artist', 'free', 0, 'MWK', 'month',
    '{
      "tier": "free",
      "upload_limit": "limited",
      "join_battles": true,
      "earn_coins": true,
      "can_withdraw": false,
      "analytics": "basic",
      "withdrawal_cap": null,
      "verification_badge": false,
      "host_events": false,
      "featured_placement": false,
      "priority_support": false
    }'::jsonb
  ),
  -- Artist Plus tier
  (
    'artist', 'plus', 3000, 'MWK', 'month',
    '{
      "tier": "plus",
      "upload_limit": "higher",
      "join_battles": true,
      "earn_coins": true,
      "can_withdraw": true,
      "analytics": "advanced",
      "withdrawal_cap": "monthly",
      "verification_badge": true,
      "host_events": false,
      "featured_placement": false,
      "priority_support": false
    }'::jsonb
  ),
  -- Artist Pro tier
  (
    'artist', 'pro', 6000, 'MWK', 'month',
    '{
      "tier": "pro",
      "upload_limit": "unlimited",
      "join_battles": true,
      "earn_coins": true,
      "can_withdraw": true,
      "analytics": "full_dashboard",
      "withdrawal_cap": "unlimited",
      "verification_badge": true,
      "host_events": true,
      "featured_placement": true,
      "priority_support": true
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
