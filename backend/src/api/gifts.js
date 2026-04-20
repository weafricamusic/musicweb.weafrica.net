const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Get gift catalog
router.get('/catalog', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('gift_catalog')
      .select('*')
      .eq('is_active', true)
      .order('tier', { ascending: true });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Send gift
router.post('/send', authenticate, async (req, res) => {
  try {
    const { battleId, recipientId, giftId, coinValue } = req.body;
    const senderId = req.user.id;

    // Check sender balance
    const { data: wallet } = await supabase
      .from('wallets')
      .select('coin_balance')
      .eq('user_id', senderId)
      .single();

    if (wallet.coin_balance < coinValue) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    // Deduct coins
    await supabase
      .from('wallets')
      .update({
        coin_balance: supabase.raw('coin_balance - ?', [coinValue]),
        updated_at: new Date()
      })
      .eq('user_id', senderId);

    // Record gift
    const { data: gift, error } = await supabase
      .from('live_gifts')
      .insert({
        battle_id: battleId,
        sender_id: senderId,
        recipient_id: recipientId,
        gift_id: giftId,
        coin_value: coinValue,
        created_at: new Date()
      })
      .select()
      .single();

    if (error) throw error;

    // Update battle scores
    const scoreField = recipientId === (await getHostAId(battleId)) ? 'host_a_score' : 'host_b_score';

    await supabase
      .from('live_battles')
      .update({
        [scoreField]: supabase.raw(`${scoreField} + ?`, [coinValue])
      })
      .eq('battle_id', battleId);

    res.json(gift);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get battle gifts
router.get('/battle/:battleId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('live_gifts')
      .select(`
        *,
        sender:users!sender_id(display_name, username),
        recipient:users!recipient_id(display_name, username)
      `)
      .eq('battle_id', req.params.battleId)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Helper function
async function getHostAId(battleId) {
  const { data } = await supabase
    .from('live_battles')
    .select('host_a_id')
    .eq('battle_id', battleId)
    .single();
  return data?.host_a_id;
}

module.exports = router;