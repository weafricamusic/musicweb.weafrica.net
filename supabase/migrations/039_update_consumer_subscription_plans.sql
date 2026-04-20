-- Update consumer subscription plans with finalized tiers
-- Free, Premium (MK 11,662.76), and Platinum (MK 17,412.66)

-- Delete old consumer plans to avoid conflicts
delete from subscription_plans where role = 'consumer' and plan like 'premium%';
-- Insert finalized consumer plans
insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  -- Free tier (already exists but ensuring it's correct)
  (
    'consumer', 'free', 0, 'MWK', 'month',
    '{
      "tier": "free",
      "ads": true,
      "limited_skips": true,
      "watch_battles": true,
      "vote_battles": false,
      "send_gifts": false,
      "downloads": false,
      "badge": "FREE"
    }'::jsonb
  ),
  -- Premium tier (mid-tier)
  (
    'consumer', 'premium', 11662.76, 'MWK', 'month',
    '{
      "tier": "premium",
      "ads": false,
      "unlimited_streaming": true,
      "watch_battles": true,
      "vote_battles": true,
      "better_audio_quality": true,
      "send_gifts": false,
      "free_coins_monthly": false,
      "discounted_coins": false,
      "downloads": false,
      "badge": "PREMIUM",
      "cancel_anytime": true,
      "audio_quality_kbps": 320
    }'::jsonb
  ),
  -- Platinum tier (top-tier)
  (
    'consumer', 'platinum', 17412.66, 'MWK', 'month',
    '{
      "tier": "platinum",
      "ads": false,
      "unlimited_streaming": true,
      "watch_battles": true,
      "vote_battles": true,
      "better_audio_quality": true,
      "send_gifts": true,
      "free_coins_monthly": true,
      "discounted_coins": true,
      "downloads": true,
      "downloads_watermarked": true,
      "badge": "PLATINUM",
      "priority_events": true,
      "highlighted_chat": true,
      "cancel_anytime": true,
      "audio_quality_kbps": 320,
      "lossless_audio": true
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
