-- Add new consumer subscription tiers: Premium Lite, Premium Standard, and Platinum
-- These replace/supplement the existing generic "premium" plan with tiered options.

insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  -- Premium Lite tier
  (
    'consumer','premium_lite',8442.50,'MWK','month',
    '{
      "tier": "lite",
      "accounts": 1,
      "audio_quality": "high",
      "audio_quality_kbps": 160,
      "offline_download": false,
      "ad_supported": true,
      "cancel_anytime": true,
      "payment_options": ["subscribe", "one_time"],
      "badge": "LITE"
    }'::jsonb
  ),
  -- Premium Standard tier
  (
    'consumer','premium_standard',12663.76,'MWK','month',
    '{
      "tier": "standard",
      "accounts": 1,
      "audio_quality": "very_high",
      "audio_quality_kbps": 320,
      "offline_download": true,
      "ad_supported": false,
      "cancel_anytime": true,
      "payment_options": ["subscribe", "one_time"],
      "badge": "STANDARD"
    }'::jsonb
  ),
  -- Platinum tier
  (
    'consumer','platinum',17412.66,'MWK','month',
    '{
      "tier": "platinum",
      "accounts": 3,
      "audio_quality": "lossless",
      "audio_quality_spec": "24-bit/44.1kHz",
      "offline_download": true,
      "ad_supported": false,
      "audiobook_listening": true,
      "playlist_mixing": true,
      "personal_ai_dj": true,
      "ai_playlist_creation": true,
      "dj_software_integration": true,
      "cancel_anytime": true,
      "payment_options": ["subscribe"],
      "badge": "PLATINUM"
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
