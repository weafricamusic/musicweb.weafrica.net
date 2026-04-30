-- ==============================================
-- LIVE COMMENTS SYSTEM
-- ==============================================

CREATE TABLE live_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE NOT NULL,
  user_id TEXT REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  username TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_comments_session ON live_comments(live_session_id);
CREATE INDEX idx_live_comments_created ON live_comments(created_at);

-- RLS
ALTER TABLE live_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Everyone can view live comments" ON live_comments
  FOR SELECT USING (true);

CREATE POLICY "Authenticated users can send comments" ON live_comments
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);

-- Real time
ALTER TABLE live_comments ENABLE REPLICA IDENTITY FULL;