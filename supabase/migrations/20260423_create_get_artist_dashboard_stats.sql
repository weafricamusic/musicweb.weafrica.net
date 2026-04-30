-- Migration: Create get_artist_dashboard_stats RPC function
-- Fixes 404 error: get_artist_dashboard_stats function not found

-- Create the get_artist_dashboard_stats function
CREATE OR REPLACE FUNCTION public.get_artist_dashboard_stats(
  p_artist_id UUID
)
RETURNS TABLE (
  followers INTEGER,
  total_plays INTEGER,
  total_earnings DOUBLE PRECISION,
  unread_messages INTEGER,
  pending_notifications INTEGER,
  songs_count INTEGER,
  videos_count INTEGER,
  battles_won INTEGER,
  battles_lost INTEGER,
  rank INTEGER
) AS $$
DECLARE
  v_user_id TEXT;
  v_artist_id UUID;
BEGIN
  -- Get the current user's ID
  v_user_id := auth.uid()::TEXT;
  
  -- Verify the artist exists and belongs to this user (or user is admin)
  SELECT a.id INTO v_artist_id
  FROM public.artists a
  WHERE a.id = p_artist_id
    AND (a.user_id = v_user_id OR EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = v_user_id AND ur.role IN ('admin', 'super_admin')
    ));
  
  IF v_artist_id IS NULL THEN
    -- Return zeros if artist not found or no permission
    RETURN QUERY SELECT
      0::INTEGER, 0::INTEGER, 0::DOUBLE PRECISION, 0::INTEGER,
      0::INTEGER, 0::INTEGER, 0::INTEGER, 0::INTEGER, 0::INTEGER, 0::INTEGER;
  END IF;
  
  RETURN QUERY
  WITH follower_count AS (
    SELECT COUNT(*) AS count
    FROM public.followers
    WHERE following_id = v_artist_id
  ),
  play_count AS (
    SELECT COALESCE(SUM(play_count), 0) AS count
    FROM public.song_plays sp
    JOIN public.songs s ON s.id = sp.song_id
    WHERE s.artist_id = v_artist_id
  ),
  earnings AS (
    SELECT COALESCE(SUM(amount), 0.0) AS total
    FROM public.wallet_transactions wt
    JOIN public.wallets w ON w.id = wt.wallet_id
    WHERE w.user_id = v_user_id AND wt.type = 'credit'
  ),
  unread_msg_count AS (
    SELECT COUNT(*) AS count
    FROM public.messages m
    WHERE m.artist_id = v_artist_id AND m.read = FALSE
  ),
  notification_count AS (
    SELECT COUNT(*) AS count
    FROM public.notifications n
    WHERE n.user_id = v_user_id AND n.read = FALSE
  ),
  song_count AS (
    SELECT COUNT(*) AS count
    FROM public.songs s
    WHERE s.artist_id = v_artist_id AND s.is_active = TRUE
  ),
  video_count AS (
    SELECT COUNT(*) AS count
    FROM public.videos v
    WHERE v.artist_id = v_artist_id AND v.is_active = TRUE
  ),
  battle_stats AS (
    SELECT 
      COUNT(CASE WHEN winner_id = v_artist_id THEN 1 END) AS won,
      COUNT(CASE WHEN loser_id = v_artist_id THEN 1 END) AS lost
    FROM public.live_battles lb
    WHERE (lb.artist1_id = v_artist_id OR lb.artist2_id = v_artist_id)
      AND lb.status = 'ended'
  ),
  artist_rank AS (
    -- Simple rank based on total plays (can be enhanced with more complex scoring)
    SELECT COUNT(*) + 1 AS rank
    FROM public.artists a2
    JOIN public.songs s2 ON s2.artist_id = a2.id
    JOIN public.song_plays sp2 ON sp2.song_id = s2.id
    WHERE a2.id != v_artist_id
    GROUP BY a2.id
    HAVING SUM(sp2.play_count) > (
      SELECT COALESCE(SUM(sp3.play_count), 0)
      FROM public.songs s3
      JOIN public.song_plays sp3 ON sp3.song_id = s3.id
      WHERE s3.artist_id = v_artist_id
    )
  )
  SELECT
    (SELECT COALESCE(count, 0)::INTEGER FROM follower_count) AS followers,
    (SELECT COALESCE(count, 0)::INTEGER FROM play_count) AS total_plays,
    (SELECT COALESCE(total, 0.0) FROM earnings) AS total_earnings,
    (SELECT COALESCE(count, 0)::INTEGER FROM unread_msg_count) AS unread_messages,
    (SELECT COALESCE(count, 0)::INTEGER FROM notification_count) AS pending_notifications,
    (SELECT COALESCE(count, 0)::INTEGER FROM song_count) AS songs_count,
    (SELECT COALESCE(count, 0)::INTEGER FROM video_count) AS videos_count,
    (SELECT COALESCE(won, 0)::INTEGER FROM battle_stats) AS battles_won,
    (SELECT COALESCE(lost, 0)::INTEGER FROM battle_stats) AS battles_lost,
    (SELECT COALESCE(MIN(rank), 1)::INTEGER FROM artist_rank) AS rank;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_artist_dashboard_stats(UUID) TO authenticated;

-- Comment the function
COMMENT ON FUNCTION public.get_artist_dashboard_stats IS 'Returns comprehensive dashboard statistics for an artist';