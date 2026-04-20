const express = require('express');
const router = express.Router();
const battleService = require('../services/battleService');
const { authenticate } = require('../middleware/auth');

// Create battle
router.post('/create', authenticate, async (req, res) => {
  try {
    const { settings } = req.body;
    const result = await battleService.createBattle(req.user.id, settings);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Join battle
router.post('/:battleId/join', authenticate, async (req, res) => {
  try {
    const result = await battleService.joinBattle(req.params.battleId, req.user.id);
    res.json(result);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Get battle
router.get('/:battleId', async (req, res) => {
  try {
    const { data, error } = await req.supabase
      .from('live_battles')
      .select('*')
      .eq('battle_id', req.params.battleId)
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(404).json({ error: 'Battle not found' });
  }
});

// Send gift
router.post('/:battleId/gift', authenticate, async (req, res) => {
  try {
    const { recipientId, giftId, giftName, coinValue } = req.body;
    const result = await battleService.processGift({
      battleId: req.params.battleId,
      senderId: req.user.id,
      recipientId,
      giftId,
      giftName,
      coinValue
    });
    res.json(result);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Set ready status
router.post('/:battleId/ready', authenticate, async (req, res) => {
  try {
    const { ready } = req.body;
    const field = req.user.id === (await battleService.getHostAId(req.params.battleId))
      ? 'host_a_ready'
      : 'host_b_ready';

    const { data, error } = await req.supabase
      .from('live_battles')
      .update({ [field]: ready })
      .eq('battle_id', req.params.battleId)
      .select()
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get active battles
router.get('/', async (req, res) => {
  try {
    const { data, error } = await req.supabase
      .from('live_battles')
      .select('*')
      .in('status', ['waiting', 'countdown', 'live'])
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;