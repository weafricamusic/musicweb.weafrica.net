-- ==============================================
-- WEAFRICA MUSIC: BATTLE REQUESTS SYSTEM
-- ==============================================
-- Two way battle request system:
--  1. host_invites_guest
--  2. viewer_challenges_host
-- ==============================================

CREATE TABLE battle_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE NOT NULL,
  requester_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  receiver_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  request_type TEXT NOT NULL CHECK (request_type IN ('host_invites_guest', 'viewer_challenges_host')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '45 seconds'
);

-- Prevent self challenge rule
ALTER TABLE battle_requests
ADD CONSTRAINT no_self_battle_request
CHECK (requester_id <> receiver_id);

-- One pending request per receiver rule (partial unique index)
CREATE UNIQUE INDEX only_one_pending_per_receiver ON battle_requests(receiver_id)
WHERE status = 'pending';

-- Indexes for performance
CREATE INDEX idx_battle_requests_live_session ON battle_requests(live_session_id);
CREATE INDEX idx_battle_requests_requester ON battle_requests(requester_id);
CREATE INDEX idx_battle_requests_receiver ON battle_requests(receiver_id);
CREATE INDEX idx_battle_requests_status ON battle_requests(status);
CREATE INDEX idx_battle_requests_expires_at ON battle_requests(expires_at);

-- ==============================================
-- RLS POLICIES
-- ==============================================
ALTER TABLE battle_requests ENABLE ROW LEVEL SECURITY;

-- Users can view requests they are involved in
CREATE POLICY "Users can view own battle requests" ON battle_requests
  FOR SELECT USING (auth.uid()::text = requester_id OR auth.uid()::text = receiver_id);

-- Users can create requests if they are artists/DJs
CREATE POLICY "Artists can create battle requests" ON battle_requests
  FOR INSERT WITH CHECK (
    auth.uid()::text = requester_id
    AND EXISTS (
      SELECT 1 FROM profiles WHERE id = requester_id AND role IN ('artist', 'dj')
    )
  );

-- Only receiver can update request status
CREATE POLICY "Only receiver can update battle requests" ON battle_requests
  FOR UPDATE USING (auth.uid()::text = receiver_id);

-- ==============================================
-- AUTO EXPIRE JOB
-- ==============================================
CREATE OR REPLACE FUNCTION expire_battle_requests()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE battle_requests
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_expire_battle_requests
  AFTER INSERT OR UPDATE ON battle_requests
  EXECUTE FUNCTION expire_battle_requests();

-- ==============================================
-- BATTLE SESSIONS
-- ==============================================
CREATE TABLE battle_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_session_host_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE NOT NULL,
  live_session_guest_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE,
  host_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  guest_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  agora_channel TEXT NOT NULL,
  duration_seconds INTEGER DEFAULT 1200,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  winner_id TEXT REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE battle_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All users can view battle sessions" ON battle_sessions FOR SELECT USING (true);

-- ==============================================
-- WHEN REQUEST IS ACCEPTED TRIGGER
-- ==============================================
CREATE OR REPLACE FUNCTION on_battle_request_accepted()
RETURNS TRIGGER AS $$
BEGIN

  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN

    INSERT INTO battle_sessions (
      live_session_host_id,
      host_id,
      guest_id,
      agora_channel
    )
    SELECT
      br.live_session_id,
      CASE
        WHEN br.request_type = 'host_invites_guest' THEN br.requester_id
        ELSE br.receiver_id
      END,
      CASE
        WHEN br.request_type = 'host_invites_guest' THEN br.receiver_id
        ELSE br.requester_id
      END,
      'battle_' || br.live_session_id::text || '_' || gen_random_uuid()::text
    FROM battle_requests br
    WHERE br.id = NEW.id;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_battle_request_accepted
AFTER UPDATE OF status ON battle_requests
FOR EACH ROW
EXECUTE FUNCTION on_battle_request_accepted();