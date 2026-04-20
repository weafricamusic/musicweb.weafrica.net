const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Get user profile
router.get('/profile/:userId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('users')
      .select(`
        *,
        wallets(*)
      `)
      .eq('id', req.params.userId)
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(404).json({ error: 'User not found' });
  }
});

// Update user profile
router.put('/profile', authenticate, async (req, res) => {
  try {
    const { displayName, bio, genre, instagram, twitter, tiktok, youtube, soundcloud } = req.body;

    const { data, error } = await supabase
      .from('users')
      .update({
        display_name: displayName,
        bio,
        genre,
        instagram,
        twitter,
        tiktok,
        youtube,
        soundcloud,
        updated_at: new Date()
      })
      .eq('id', req.user.id)
      .select()
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get user wallet
router.get('/wallet', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('wallets')
      .select('*')
      .eq('user_id', req.user.id)
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(404).json({ error: 'Wallet not found' });
  }
});

// Get user battle history
router.get('/battles', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('live_battles')
      .select('*')
      .or(`host_a_id.eq.${req.user.id},host_b_id.eq.${req.user.id}`)
      .eq('status', 'ended')
      .order('ended_at', { ascending: false })
      .limit(20);

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get user stats
router.get('/stats', authenticate, async (req, res) => {
  try {
    const { data: user } = await supabase
      .from('users')
      .select('total_battles, total_wins, total_losses, total_coins_earned')
      .eq('id', req.user.id)
      .single();

    const { data: wallet } = await supabase
      .from('wallets')
      .select('coin_balance, total_coins_earned, total_coins_spent')
      .eq('user_id', req.user.id)
      .single();

    res.json({
      battles: {
        total: user?.total_battles || 0,
        wins: user?.total_wins || 0,
        losses: user?.total_losses || 0,
        winRate: user?.total_battles > 0 ? (user.total_wins / user.total_battles * 100).toFixed(1) : 0
      },
      coins: {
        balance: wallet?.coin_balance || 0,
        totalEarned: wallet?.total_coins_earned || 0,
        totalSpent: wallet?.total_coins_spent || 0
      }
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Follow user
router.post('/follow/:userId', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('follows')
      .insert({
        follower_id: req.user.id,
        following_id: req.params.userId
      })
      .select()
      .single();

    if (error) throw error;

    // Update follower counts
    await supabase
      .from('users')
      .update({ followers_count: supabase.raw('followers_count + 1') })
      .eq('id', req.params.userId);

    await supabase
      .from('users')
      .update({ following_count: supabase.raw('following_count + 1') })
      .eq('id', req.user.id);

    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Unfollow user
router.delete('/follow/:userId', authenticate, async (req, res) => {
  try {
    const { error } = await supabase
      .from('follows')
      .delete()
      .eq('follower_id', req.user.id)
      .eq('following_id', req.params.userId);

    if (error) throw error;

    // Update follower counts
    await supabase
      .from('users')
      .update({ followers_count: supabase.raw('followers_count - 1') })
      .eq('id', req.params.userId);

    await supabase
      .from('users')
      .update({ following_count: supabase.raw('following_count - 1') })
      .eq('id', req.user.id);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;