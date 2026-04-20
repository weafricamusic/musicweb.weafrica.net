const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

class GiftService {
  // Get gift catalog
  async getGiftCatalog() {
    try {
      const { data, error } = await supabase
        .from('gift_catalog')
        .select('*')
        .eq('is_active', true)
        .order('tier', { ascending: true });

      if (error) throw error;
      return data;
    } catch (error) {
      throw error;
    }
  }

  // Get battle gifts
  async getBattleGifts(battleId) {
    try {
      const { data, error } = await supabase
        .from('live_gifts')
        .select(`
          *,
          sender:users!sender_id(display_name, username),
          recipient:users!recipient_id(display_name, username)
        `)
        .eq('battle_id', battleId)
        .order('created_at', { ascending: false });

      if (error) throw error;
      return data;
    } catch (error) {
      throw error;
    }
  }

  // Send gift (already handled in battle service, but keeping for consistency)
  async sendGift(giftData) {
    // This is handled by battleService.processGift
    // Keeping this for potential future expansion
    return giftData;
  }
}

module.exports = new GiftService();