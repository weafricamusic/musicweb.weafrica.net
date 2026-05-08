-- Create subscription_plans table if it doesn't exist
CREATE TABLE IF NOT EXISTS subscription_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id TEXT NOT NULL UNIQUE,
  audience TEXT NOT NULL,
  role TEXT NOT NULL,
  plan TEXT NOT NULL,
  name TEXT NOT NULL,
  price INTEGER NOT NULL,
  price_mwk INTEGER NOT NULL,
  billing_interval TEXT NOT NULL DEFAULT 'month',
  currency TEXT NOT NULL DEFAULT 'MWK',
  active BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  features JSONB NOT NULL DEFAULT '{}',
  marketing JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add unique constraint for legacy compatibility
ALTER TABLE subscription_plans 
  ADD CONSTRAINT subscription_plans_role_plan_interval_unique 
  UNIQUE (role, plan, billing_interval);

-- Insert or update plans
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
  updated_at = NOW();
