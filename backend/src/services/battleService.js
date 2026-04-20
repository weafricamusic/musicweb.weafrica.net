const { createClient } = require('@supabase/supabase-js');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const redis = require('../config/redis');
const logger = require('../utils/logger');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

class BattleService {
  // Generate Agora token
  static generateToken(channelName, uid, role = 'broadcaster') {
    const expirationTimeInSeconds = 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    const token = RtcTokenBuilder.buildTokenWithUid(
      process.env.AGORA_APP_ID,
      process.env.AGORA_APP_CERTIFICATE,
      channelName,
      uid,
      role === 'broadcaster' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER,
      privilegeExpiredTs
    );

    return token;
  }

  // Create new battle
  async createBattle(hostId, settings = {}) {
    try {
      const channelName = `battle_${Date.now()}_${Math.random().toString(36).substring(7)}`;

      const { data, error } = await supabase
        .from('live_battles')
        .insert({
          battle_id: `battle_${Date.now()}`,
          channel_id: channelName,
          status: 'waiting',
          host_a_id: hostId,
          created_at: new Date()
        })
        .select()
        .single();

      if (error) throw error;

      // Generate tokens
      const hostAToken = BattleService.generateToken(channelName, hostId, 'broadcaster');
      const viewerToken = BattleService.generateToken(channelName, 'viewer', 'audience');

      // Cache battle in Redis
      await redis.setex(`battle:${data.battle_id}`, 3600, JSON.stringify(data));

      return {
        battle: data,
        tokens: {
          hostA: hostAToken,
          viewer: viewerToken
        }
      };
    } catch (error) {
      logger.error('Create battle error:', error);
      throw error;
    }
  }

  // Join battle
  async joinBattle(battleId, hostBId) {
    try {
      // Check if battle exists
      const { data: battle, error: fetchError } = await supabase
        .from('live_battles')
        .select('*')
        .eq('battle_id', battleId)
        .single();

      if (fetchError || !battle) {
        throw new Error('Battle not found');
      }

      if (battle.host_b_id) {
        throw new Error('Battle already has two hosts');
      }

      // Update battle
      const { data, error } = await supabase
        .from('live_battles')
        .update({
          host_b_id: hostBId,
          status: 'countdown',
          updated_at: new Date()
        })
        .eq('battle_id', battleId)
        .select()
        .single();

      if (error) throw error;

      // Generate token for host B
      const token = BattleService.generateToken(
        battle.channel_id,
        hostBId,
        'broadcaster'
      );

      // Start countdown
      this.startCountdown(battleId);

      return {
        battle: data,
        token: token
      };
    } catch (error) {
      logger.error('Join battle error:', error);
      throw error;
    }
  }

  // Start countdown
  async startCountdown(battleId) {
    const countdown = 10;

    for (let i = countdown; i >= 0; i--) {
      // Broadcast countdown via Redis pub/sub
      await redis.publish(`battle:${battleId}`, JSON.stringify({
        type: 'countdown',
        seconds: i,
        timestamp: Date.now()
      }));

      await new Promise(resolve => setTimeout(resolve, 1000));

      if (i === 0) {
        // Start battle
        await supabase
          .from('live_battles')
          .update({
            status: 'live',
            started_at: new Date()
          })
          .eq('battle_id', battleId);

        // Broadcast battle start
        await redis.publish(`battle:${battleId}`, JSON.stringify({
          type: 'battle-start',
          timestamp: Date.now()
        }));

        // Start round timer
        this.startRoundTimer(battleId);
      }
    }
  }

  // Start round timer
  async startRoundTimer(battleId) {
    const roundDuration = 120; // 2 minutes
    let roundSeconds = roundDuration;

    const timer = setInterval(async () => {
      roundSeconds--;

      // Broadcast round time
      await redis.publish(`battle:${battleId}`, JSON.stringify({
        type: 'round-time',
        seconds: roundSeconds,
        timestamp: Date.now()
      }));

      if (roundSeconds <= 0) {
        clearInterval(timer);
        await this.endBattle(battleId);
      }
    }, 1000);
  }

  // Process gift
  async processGift(data) {
    const {
      battleId,
      senderId,
      recipientId,
      giftId,
      giftName,
      coinValue
    } = data;

    try {
      // Check sender balance
      const { data: wallet } = await supabase
        .from('wallets')
        .select('coin_balance')
        .eq('user_id', senderId)
        .single();

      if (wallet.coin_balance < coinValue) {
        throw new Error('Insufficient balance');
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
          gift_name: giftName,
          coin_value: coinValue,
          created_at: new Date()
        })
        .select()
        .single();

      if (error) throw error;

      // Update battle scores
      const scoreField = recipientId === (await this.getHostAId(battleId)) ? 'host_a_score' : 'host_b_score';

      await supabase
        .from('live_battles')
        .update({
          [scoreField]: supabase.raw(`${scoreField} + ?`, [coinValue])
        })
        .eq('battle_id', battleId);

      // Broadcast gift
      await redis.publish(`battle:${battleId}`, JSON.stringify({
        type: 'gift',
        data: gift,
        timestamp: Date.now()
      }));

      return gift;
    } catch (error) {
      logger.error('Process gift error:', error);
      throw error;
    }
  }

  // End battle
  async endBattle(battleId) {
    try {
      const { data: battle } = await supabase
        .from('live_battles')
        .select('*')
        .eq('battle_id', battleId)
        .single();

      // Determine winner
      let winnerId = null;
      if (battle.host_a_score > battle.host_b_score) {
        winnerId = battle.host_a_id;
      } else if (battle.host_b_score > battle.host_a_score) {
        winnerId = battle.host_b_id;
      }

      // Update battle
      await supabase
        .from('live_battles')
        .update({
          status: 'ended',
          ended_at: new Date(),
          winner_id: winnerId
        })
        .eq('battle_id', battleId);

      // Distribute rewards if applicable
      if (winnerId) {
        await this.distributeRewards(battleId, winnerId, battle.prize_pool || 0);
      }

      // Broadcast battle end
      await redis.publish(`battle:${battleId}`, JSON.stringify({
        type: 'battle-end',
        winner: winnerId,
        scores: {
          hostA: battle.host_a_score,
          hostB: battle.host_b_score
        },
        timestamp: Date.now()
      }));

      return { winner: winnerId };
    } catch (error) {
      logger.error('End battle error:', error);
      throw error;
    }
  }

  // Helper methods
  async getHostAId(battleId) {
    const { data } = await supabase
      .from('live_battles')
      .select('host_a_id')
      .eq('battle_id', battleId)
      .single();
    return data?.host_a_id;
  }

  async distributeRewards(battleId, winnerId, prizePool) {
    if (prizePool <= 0) return;

    // 70% to winner, 30% to loser
    const winnerShare = Math.floor(prizePool * 0.7);
    const loserShare = Math.floor(prizePool * 0.3);

    // Get loser ID
    const { data: battle } = await supabase
      .from('live_battles')
      .select('host_a_id, host_b_id')
      .eq('battle_id', battleId)
      .single();

    const loserId = battle.host_a_id === winnerId ? battle.host_b_id : battle.host_a_id;

    // Update winner wallet
    await supabase
      .from('wallets')
      .update({
        coin_balance: supabase.raw('coin_balance + ?', [winnerShare])
      })
      .eq('user_id', winnerId);

    // Update loser wallet
    if (loserId) {
      await supabase
        .from('wallets')
        .update({
          coin_balance: supabase.raw('coin_balance + ?', [loserShare])
        })
        .eq('user_id', loserId);
    }
  }
}

module.exports = new BattleService();