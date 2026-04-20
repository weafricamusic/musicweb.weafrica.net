const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Get battle analytics
router.get('/battle/:battleId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('battle_analytics')
      .select('*')
      .eq('battle_id', req.params.battleId)
      .order('timestamp', { ascending: false })
      .limit(100);

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Record battle heartbeat
router.post('/battle/:battleId/heartbeat', async (req, res) => {
  try {
    const { viewerCount, hostAScore, hostBScore, giftsLastMinute, messagesLastMinute } = req.body;

    const { data, error } = await supabase
      .from('battle_analytics')
      .insert({
        battle_id: req.params.battleId,
        timestamp: new Date(),
        viewer_count: viewerCount || 0,
        host_a_score: hostAScore || 0,
        host_b_score: hostBScore || 0,
        gifts_last_minute: giftsLastMinute || 0,
        messages_last_minute: messagesLastMinute || 0
      })
      .select()
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get user analytics
router.get('/user/:userId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('user_analytics')
      .select('*')
      .eq('user_id', req.params.userId)
      .order('date', { ascending: false })
      .limit(30);

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get top battles
router.get('/battles/top', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('live_battles')
      .select('*')
      .eq('status', 'ended')
      .order('total_coins_earned', { ascending: false })
      .limit(10);

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get platform stats
router.get('/platform/stats', async (req, res) => {
  try {
    // Get total battles
    const { count: totalBattles } = await supabase
      .from('live_battles')
      .select('*', { count: 'exact', head: true });

    // Get active battles
    const { count: activeBattles } = await supabase
      .from('live_battles')
      .select('*', { count: 'exact', head: true })
      .in('status', ['waiting', 'countdown', 'live']);

    // Get total gifts
    const { count: totalGifts } = await supabase
      .from('live_gifts')
      .select('*', { count: 'exact', head: true });

    // Get total coins earned
    const { data: coinsData } = await supabase
      .from('live_battles')
      .select('total_coins_earned')
      .single();

    const totalCoinsEarned = coinsData?.total_coins_earned || 0;

    res.json({
      totalBattles,
      activeBattles,
      totalGifts,
      totalCoinsEarned
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;