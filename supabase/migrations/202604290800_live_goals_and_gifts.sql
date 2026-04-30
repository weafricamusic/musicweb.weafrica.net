-- ==============================================
-- WEAFRICA MUSIC: LIVE GOALS & GIFT SYSTEM
-- Firebase UID compatible
-- ==============================================

DROP TABLE IF EXISTS gift_transactions CASCADE;
DROP TABLE IF EXISTS live_goals CASCADE;
DROP TABLE IF EXISTS gifts CASCADE;

-- ==============================================
-- GIFTS
-- ==============================================

CREATE TABLE gifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  coin_value INTEGER NOT NULL DEFAULT 1 CHECK (coin_value > 0),
  icon TEXT NOT NULL,
  color TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('rose', 'fire', 'diamond', 'crown', 'premium', 'special')),
  animation_url TEXT,
  sound_url TEXT,
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO gifts (name, coin_value, icon, color, type, sort_order) VALUES
('Rose', 1, '🌹', '#FF4081', 'rose', 0),
('Fire', 5, '🔥', '#FF6D00', 'fire', 1),
('Diamond', 25, '💎', '#00E5FF', 'diamond', 2),
('Crown', 100, '👑', '#FFD600', 'crown', 3);

-- ==============================================
-- LIVE GOALS
-- ==============================================

CREATE TABLE live_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE NOT NULL,
  created_by TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,

  goal_type TEXT NOT NULL CHECK (goal_type IN ('gift', 'coins', 'viewers')),
  gift_type TEXT CHECK (gift_type IN ('rose', 'fire', 'diamond', 'crown')),

  target INTEGER NOT NULL CHECK (target > 0),
  current INTEGER NOT NULL DEFAULT 0 CHECK (current >= 0),

  reward_text TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),

  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT gift_goal_requires_gift_type CHECK (
    (goal_type = 'gift' AND gift_type IS NOT NULL)
    OR
    (goal_type IN ('coins', 'viewers') AND gift_type IS NULL)
  )
);

CREATE INDEX idx_live_goals_session ON live_goals(live_session_id);
CREATE INDEX idx_live_goals_status ON live_goals(status);
CREATE INDEX idx_live_goals_created_by ON live_goals(created_by);

-- One active goal per live session for now
CREATE UNIQUE INDEX only_one_active_goal_per_live
ON live_goals(live_session_id)
WHERE status = 'active';

-- ==============================================
-- GIFT TRANSACTIONS
-- ==============================================

CREATE TABLE gift_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  live_session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE NOT NULL,
  battle_session_id UUID REFERENCES battle_sessions(id) ON DELETE CASCADE,

  sender_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  receiver_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,

  gift_id UUID REFERENCES gifts(id) ON DELETE CASCADE NOT NULL,

  amount INTEGER NOT NULL DEFAULT 1 CHECK (amount > 0),
  total_coins INTEGER NOT NULL CHECK (total_coins > 0),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_gift_transactions_session ON gift_transactions(live_session_id);
CREATE INDEX idx_gift_transactions_sender ON gift_transactions(sender_id);
CREATE INDEX idx_gift_transactions_receiver ON gift_transactions(receiver_id);
CREATE INDEX idx_gift_transactions_battle ON gift_transactions(battle_session_id);
CREATE INDEX idx_gift_transactions_created ON gift_transactions(created_at);

-- ==============================================
-- RLS
-- Firebase testing-friendly policies
-- ==============================================

ALTER TABLE gifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Everyone can view gifts"
ON gifts FOR SELECT
USING (true);

CREATE POLICY "Everyone can view live goals"
ON live_goals FOR SELECT
USING (true);

CREATE POLICY "Allow artists and djs to create goals"
ON live_goals FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM profiles
    WHERE profiles.id = created_by
    AND profiles.role IN ('artist', 'dj')
  )
);

CREATE POLICY "Allow goal owner to update goal"
ON live_goals FOR UPDATE
USING (true)
WITH CHECK (true);

CREATE POLICY "Everyone can view gift transactions"
ON gift_transactions FOR SELECT
USING (true);

CREATE POLICY "Allow users to send gifts"
ON gift_transactions FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM profiles
    WHERE profiles.id = sender_id
  )
);

-- ==============================================
-- AUTO CALCULATE TOTAL COINS
-- ==============================================

CREATE OR REPLACE FUNCTION calculate_gift_total_coins()
RETURNS TRIGGER AS $$
DECLARE
  v_coin_value INTEGER;
BEGIN
  SELECT coin_value INTO v_coin_value
  FROM gifts
  WHERE id = NEW.gift_id
  AND is_active = true;

  IF v_coin_value IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive gift';
  END IF;

  NEW.total_coins := v_coin_value * NEW.amount;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_gift_total_coins
BEFORE INSERT ON gift_transactions
FOR EACH ROW
EXECUTE FUNCTION calculate_gift_total_coins();

-- ==============================================
-- UPDATE GOAL WHEN GIFT IS SENT
-- ==============================================

CREATE OR REPLACE FUNCTION update_goal_on_gift()
RETURNS TRIGGER AS $$
DECLARE
  v_gift_type TEXT;
BEGIN
  SELECT type INTO v_gift_type
  FROM gifts
  WHERE id = NEW.gift_id;

  -- Gift-specific goals: Rose, Fire, Diamond, Crown
  UPDATE live_goals
  SET current = current + NEW.amount
  WHERE live_session_id = NEW.live_session_id
    AND status = 'active'
    AND goal_type = 'gift'
    AND gift_type = v_gift_type;

  -- Coin goals: count all gift coin value
  UPDATE live_goals
  SET current = current + NEW.total_coins
  WHERE live_session_id = NEW.live_session_id
    AND status = 'active'
    AND goal_type = 'coins';

  -- Complete goals
  UPDATE live_goals
  SET status = 'completed',
      completed_at = NOW()
  WHERE live_session_id = NEW.live_session_id
    AND status = 'active'
    AND current >= target;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_goal_on_gift
AFTER INSERT ON gift_transactions
FOR EACH ROW
EXECUTE FUNCTION update_goal_on_gift();

-- ==============================================
-- REALTIME
-- ==============================================

ALTER TABLE live_goals REPLICA IDENTITY FULL;
ALTER TABLE gift_transactions REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE live_goals;
ALTER PUBLICATION supabase_realtime ADD TABLE gift_transactions;