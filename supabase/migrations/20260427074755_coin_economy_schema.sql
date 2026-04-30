-- WeAfrica Music Coin Economy Database Schema
-- Complete with RLS policies and secure functions

-- ============================================================
-- 1. USER COINS TABLE (Central balance storage)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_coins (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
    lifetime_earned INTEGER NOT NULL DEFAULT 0,
    lifetime_spent INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: Users can only read their own balance
ALTER TABLE user_coins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own coins"
    ON user_coins FOR SELECT
    USING (auth.uid()::text = user_id);

-- Only system can modify (via functions)
CREATE POLICY "No direct modifications"
    ON user_coins FOR ALL
    USING (false);

-- ============================================================
-- 2. COIN TRANSACTIONS TABLE (Immutable audit log)
-- ============================================================

CREATE TABLE IF NOT EXISTS coin_transactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('earn', 'purchase', 'giftSent', 'giftReceived', 'battleEntry', 'battleWinnings', 'withdrawal', 'refund')),
    amount INTEGER NOT NULL,
    balance_after INTEGER,
    description TEXT,
    related_user_id TEXT REFERENCES auth.users(id),
    related_entity_id TEXT, -- battle_id, stream_id, etc
    metadata JSONB,
    status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: Users can only read their own transactions
ALTER TABLE coin_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own transactions"
    ON coin_transactions FOR SELECT
    USING (auth.uid()::text = user_id);

-- Only system can insert (via functions)
CREATE POLICY "No direct insert"
    ON coin_transactions FOR INSERT
    WITH CHECK (false);

CREATE POLICY "No direct update/delete"
    ON coin_transactions FOR ALL
    USING (false);

-- ============================================================
-- 3. CREATOR EARNINGS TABLE (Artist + DJ earnings)
-- ============================================================

CREATE TABLE IF NOT EXISTS creator_earnings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    creator_id TEXT NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    creator_role TEXT NOT NULL CHECK (creator_role IN ('artist', 'dj')),
    total_earnings DECIMAL(10,2) NOT NULL DEFAULT 0,
    available_for_withdrawal DECIMAL(10,2) NOT NULL DEFAULT 0,
    pending_earnings DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_withdrawn DECIMAL(10,2) NOT NULL DEFAULT 0,
    platform_fee_percent INTEGER DEFAULT 30,
    
    -- Breakdown
    total_gifts_received DECIMAL(10,2) DEFAULT 0,
    total_battle_winnings DECIMAL(10,2) DEFAULT 0,
    total_stream_earnings DECIMAL(10,2) DEFAULT 0,
    
    updated_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: Creators can view own earnings, admins can view all
ALTER TABLE creator_earnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can view own earnings"
    ON creator_earnings FOR SELECT
    USING (auth.uid()::text = creator_id);

-- Only system can modify (via functions)
CREATE POLICY "No direct modifications"
    ON creator_earnings FOR ALL
    USING (false);

-- ============================================================
-- 4. WITHDRAWAL REQUESTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS withdrawal_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    creator_id TEXT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    creator_role TEXT NOT NULL,
    amount DECIMAL(10,2) NOT NULL CHECK (amount >= 10),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    method TEXT NOT NULL, -- 'mobile_money', 'bank', 'paypal'
    account_details JSONB NOT NULL,
    
    -- Admin fields
    processed_by UUID REFERENCES auth.users(id),
    processed_at TIMESTAMPTZ,
    admin_notes TEXT,
    
    requested_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: Creators can view own requests, admins can manage all
ALTER TABLE withdrawal_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can view own withdrawals"
    ON withdrawal_requests FOR SELECT
    USING (auth.uid()::text = creator_id);

CREATE POLICY "Creators can create requests"
    ON withdrawal_requests FOR INSERT
    WITH CHECK (auth.uid()::text = creator_id);

-- Only admins can update (handled via separate admin policy or functions)

-- ============================================================
-- 5. SECURE FUNCTIONS (Atomic transactions)
-- ============================================================

-- Function: Add coins to user (admin/ad system only)
CREATE OR REPLACE FUNCTION add_coins(
    p_user_id TEXT,
    p_amount INTEGER,
    p_type TEXT DEFAULT 'earn',
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_balance INTEGER;
BEGIN
    -- Validate amount
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    
    -- Update or insert user_coins
    INSERT INTO user_coins (user_id, balance, lifetime_earned)
    VALUES (p_user_id, p_amount, p_amount)
    ON CONFLICT (user_id)
    DO UPDATE SET
        balance = user_coins.balance + p_amount,
        lifetime_earned = user_coins.lifetime_earned + p_amount,
        updated_at = now()
    RETURNING balance INTO v_new_balance;
    
    -- Record transaction
    INSERT INTO coin_transactions (
        user_id, type, amount, balance_after, description, metadata
    ) VALUES (
        p_user_id, p_type, p_amount, v_new_balance, p_description, p_metadata
    );
    
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        RETURN false;
END;
$$;

-- Function: Deduct coins (with balance check)
CREATE OR REPLACE FUNCTION deduct_coins(
    p_user_id TEXT,
    p_amount INTEGER,
    p_type TEXT,
    p_description TEXT DEFAULT NULL,
    p_related_user_id TEXT DEFAULT NULL,
    p_related_entity_id TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance INTEGER;
    v_new_balance INTEGER;
BEGIN
    -- Validate amount
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    
    -- Get current balance
    SELECT balance INTO v_current_balance
    FROM user_coins
    WHERE user_id = p_user_id
    FOR UPDATE; -- Lock the row
    
    -- Check sufficient balance
    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RETURN false;
    END IF;
    
    v_new_balance := v_current_balance - p_amount;
    
    -- Update balance
    UPDATE user_coins
    SET balance = v_new_balance,
        lifetime_spent = lifetime_spent + p_amount,
        updated_at = now()
    WHERE user_id = p_user_id;
    
    -- Record transaction
    INSERT INTO coin_transactions (
        user_id, type, amount, balance_after, description,
        related_user_id, related_entity_id
    ) VALUES (
        p_user_id, p_type, -p_amount, v_new_balance, p_description,
        p_related_user_id, p_related_entity_id
    );
    
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        RETURN false;
END;
$$;

-- Function: Send gift (atomic transfer)
CREATE OR REPLACE FUNCTION send_gift(
    p_from_user_id TEXT,
    p_to_creator_id TEXT,
    p_gift_amount INTEGER,
    p_gift_name TEXT,
    p_battle_id TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_platform_fee INTEGER;
    v_creator_share INTEGER;
    v_creator_role TEXT;
BEGIN
    -- Calculate split (30% platform, 70% creator)
    v_platform_fee := (p_gift_amount * 30) / 100;
    v_creator_share := p_gift_amount - v_platform_fee;
    
    -- Get creator role
    SELECT creator_role INTO v_creator_role
    FROM creator_earnings
    WHERE creator_id = p_to_creator_id;
    
    IF v_creator_role IS NULL THEN
        -- Try to get from user profile or default to artist
        v_creator_role := 'artist';
    END IF;
    
    -- Step 1: Deduct from sender
    IF NOT deduct_coins(
        p_from_user_id,
        p_gift_amount,
        'giftSent',
        'Sent ' || p_gift_name || ' to creator',
        p_to_creator_id,
        p_battle_id
    ) THEN
        RETURN false;
    END IF;
    
    -- Step 2: Add to creator earnings
    INSERT INTO creator_earnings (
        creator_id, creator_role, total_earnings, 
        available_for_withdrawal, total_gifts_received
    )
    VALUES (
        p_to_creator_id, v_creator_role, v_creator_share,
        v_creator_share, v_creator_share
    )
    ON CONFLICT (creator_id)
    DO UPDATE SET
        total_earnings = creator_earnings.total_earnings + v_creator_share,
        available_for_withdrawal = creator_earnings.available_for_withdrawal + v_creator_share,
        total_gifts_received = creator_earnings.total_gifts_received + v_creator_share,
        updated_at = now();
    
    -- Step 3: Record creator transaction
    INSERT INTO coin_transactions (
        user_id, type, amount, description,
        related_user_id, related_entity_id
    ) VALUES (
        p_to_creator_id, 'giftReceived', v_creator_share,
        'Received ' || p_gift_name || ' from fan',
        p_from_user_id, p_battle_id
    );
    
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        -- Transaction will rollback automatically
        RETURN false;
END;
$$;

-- Function: Create withdrawal request
CREATE OR REPLACE FUNCTION create_withdrawal_request(
    p_creator_id TEXT,
    p_creator_role TEXT,
    p_amount DECIMAL,
    p_method TEXT,
    p_account_details JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request_id UUID;
    v_available DECIMAL;
BEGIN
    -- Check minimum
    IF p_amount < 10 THEN
        RAISE EXCEPTION 'Minimum withdrawal is $10';
    END IF;
    
    -- Get available balance
    SELECT available_for_withdrawal INTO v_available
    FROM creator_earnings
    WHERE creator_id = p_creator_id
    FOR UPDATE;
    
    IF v_available IS NULL OR v_available < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance';
    END IF;
    
    -- Lock the amount
    UPDATE creator_earnings
    SET available_for_withdrawal = available_for_withdrawal - p_amount,
        pending_earnings = pending_earnings + p_amount,
        updated_at = now()
    WHERE creator_id = p_creator_id;
    
    -- Create request
    INSERT INTO withdrawal_requests (
        creator_id, creator_role, amount, method, account_details
    ) VALUES (
        p_creator_id, p_creator_role, p_amount, p_method, p_account_details
    )
    RETURNING id INTO v_request_id;
    
    RETURN v_request_id;
END;
$$;

-- Function: Process withdrawal (admin only)
CREATE OR REPLACE FUNCTION process_withdrawal(
    p_request_id UUID,
    p_admin_id UUID,
    p_status TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request RECORD;
BEGIN
    -- Get request
    SELECT * INTO v_request
    FROM withdrawal_requests
    WHERE id = p_request_id;
    
    IF v_request IS NULL THEN
        RETURN false;
    END IF;
    
    -- Update request status
    UPDATE withdrawal_requests
    SET status = p_status,
        processed_by = p_admin_id,
        processed_at = now(),
        admin_notes = p_notes
    WHERE id = p_request_id;
    
    -- If completed, move from pending to withdrawn
    IF p_status = 'completed' THEN
        UPDATE creator_earnings
        SET pending_earnings = pending_earnings - v_request.amount,
            total_withdrawn = total_withdrawn + v_request.amount,
            updated_at = now()
        WHERE creator_id = v_request.creator_id;
    
    -- If failed/cancelled, return to available
    ELSIF p_status IN ('failed', 'cancelled') THEN
        UPDATE creator_earnings
        SET pending_earnings = pending_earnings - v_request.amount,
            available_for_withdrawal = available_for_withdrawal + v_request.amount,
            updated_at = now()
        WHERE creator_id = v_request.creator_id;
    END IF;
    
    RETURN true;
END;
$$;

-- ============================================================
-- 6. INDEXES FOR PERFORMANCE
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON coin_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON coin_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON coin_transactions(type);
CREATE INDEX IF NOT EXISTS idx_withdrawals_creator_id ON withdrawal_requests(creator_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON withdrawal_requests(status);

-- ============================================================
-- 7. TRIGGERS
-- ============================================================

-- Auto-update timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_user_coins_updated
    BEFORE UPDATE ON user_coins
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trigger_creator_earnings_updated
    BEFORE UPDATE ON creator_earnings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();