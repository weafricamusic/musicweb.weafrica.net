-- First, drop the problematic constraints temporarily
ALTER TABLE subscription_plans DROP CONSTRAINT IF EXISTS idx_subscription_plans_role_plan_interval;
ALTER TABLE subscription_plans DROP CONSTRAINT IF EXISTS subscription_plans_plan_id_unique;

-- Remove any duplicate rows (keep the most complete one)
DELETE FROM subscription_plans a USING subscription_plans b
WHERE a.role = b.role 
  AND a.plan = b.plan 
  AND COALESCE(a.billing_interval, 'month') = COALESCE(b.billing_interval, 'month')
  AND a.ctid < b.ctid;

-- Re-add the unique constraints with proper names
ALTER TABLE subscription_plans 
  ADD CONSTRAINT subscription_plans_role_plan_interval_unique 
  UNIQUE (role, plan, billing_interval);

ALTER TABLE subscription_plans 
  ADD CONSTRAINT subscription_plans_plan_id_unique 
  UNIQUE (plan_id);

-- Ensure all billing_interval values are valid
UPDATE subscription_plans 
SET billing_interval = 'month' 
WHERE billing_interval IS NULL 
   OR billing_interval NOT IN ('month', 'week');

-- Now do the actual data seeding using ON CONFLICT
INSERT INTO subscription_plans (
  plan_id, audience, role, plan, name, price, price_mwk,
  billing_interval, currency, active, sort_order, features, marketing
) VALUES 
(
  'free', 'consumer', 'consumer', 'free', 'Free',
  0, 0, 'month', 'MWK', true, 0,
  '{"ads":true}'::jsonb,
  '{"tagline":"Listen for free","bullets":["Ad-supported listening"]}'::jsonb
),
(
  'premium', 'consumer', 'consumer', 'premium', 'Premium',
  15000, 15000, 'month', 'MWK', true, 10,
  '{"ads":false,"offline":true,"audio_quality":"320kbps","create_playlist":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
  '{"tagline":"Offline listening + live battles.","bullets":["Download to listen offline","High audio quality up to 320 kbps","Create playlists","Watch live artists/DJs battles","Cancel anytime"]}'::jsonb
),
(
  'platinum', 'consumer', 'consumer', 'platinum', 'Platinum',
  20000, 20000, 'month', 'MWK', true, 20,
  '{"ads":false,"offline":true,"audio_quality":"24bit/44.1kHz","mix_playlist":true,"ai_dj":true,"watch_live_battles":true,"cancel_anytime":true}'::jsonb,
  '{"tagline":"Studio quality + AI DJ.","bullets":["Download to listen offline","Audio quality up to 24-bit/44.1kHz","Mix your playlist","Your personal AI DJ","Watch live artists/DJs battle streaming","Cancel anytime"]}'::jsonb
)
ON CONFLICT (plan_id) DO UPDATE SET
  name = EXCLUDED.name,
  price = EXCLUDED.price,
  price_mwk = EXCLUDED.price_mwk,
  features = EXCLUDED.features,
  marketing = EXCLUDED.marketing,
  sort_order = EXCLUDED.sort_order,
  active = EXCLUDED.active,
  audience = EXCLUDED.audience,
  role = EXCLUDED.role,
  plan = EXCLUDED.plan,
  billing_interval = EXCLUDED.billing_interval,
  currency = EXCLUDED.currency;
