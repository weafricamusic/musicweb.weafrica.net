/**
 * Voting Service for Multi-Battle System
 * 
 * Handles vote counting, validation, and real-time updates
 * for simultaneous battles with multiple participants.
 */

const { createClient } = require('@supabase/supabase-js');
const redis = require('../config/redis');
const logger = require('../utils/logger');

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
);

class VotingService {
    /**
     * Cast a vote for a battle participant
     * @param {Object} params - Vote parameters
     * @param {string} params.battleId - Battle ID
     * @param {string} params.voterId - User casting the vote
     * @param {string} params.candidateId - Candidate being voted for
     * @param {string} params.voteType - Type of vote (e.g., 'regular', 'gift', 'super')
     * @param {number} params.weight - Vote weight (default: 1)
     */
    async castVote({ battleId, voterId, candidateId, voteType = 'regular', weight = 1 }) {
        const voteKey = `vote:${battleId}:${voterId}`;

        try {
            // Check if user already voted (prevent duplicate votes for regular votes)
            if (voteType === 'regular') {
                const existingVote = await redis.get(voteKey);
                if (existingVote) {
                    throw new Error('User has already voted in this battle');
                }
            }

            // Verify battle is in voting state
            const { data: battle } = await supabase
                .from('live_battles')
                .select('status, ended_at')
                .eq('battle_id', battleId)
                .single();

            if (!battle) {
                throw new Error('Battle not found');
            }

            if (battle.status !== 'live' && battle.status !== 'voting') {
                throw new Error('Battle is not accepting votes');
            }

            // Record vote in database
            const { data: vote, error } = await supabase
                .from('battle_votes')
                .insert({
                    battle_id: battleId,
                    voter_id: voterId,
                    candidate_id: candidateId,
                    vote_type: voteType,
                    weight: weight,
                    created_at: new Date()
                })
                .select()
                .single();

            if (error) throw error;

            // Cache vote in Redis for fast counting
            await redis.setex(voteKey, 3600, JSON.stringify({
                candidateId,
                voteType,
                weight,
                timestamp: Date.now()
            }));

            // Update real-time vote count in Redis
            const voteCountKey = `votes:${battleId}:${candidateId}`;
            await redis.incrby(voteCountKey, weight);

            // Broadcast vote via Redis pub/sub
            await redis.publish(`battle:${battleId}`, JSON.stringify({
                type: 'vote',
                data: {
                    voterId,
                    candidateId,
                    weight,
                    voteType,
                    timestamp: Date.now()
                }
            }));

            logger.info(`Vote cast: battle=${battleId}, voter=${voterId}, candidate=${candidateId}, weight=${weight}`);

            return vote;
        } catch (error) {
            logger.error('Cast vote error:', error);
            throw error;
        }
    }

    /**
     * Get current vote counts for a battle
     * @param {string} battleId - Battle ID
     * @param {Array<string>} candidateIds - List of candidate IDs
     */
    async getVoteCounts(battleId, candidateIds) {
        try {
            const voteCounts = {};

            for (const candidateId of candidateIds) {
                const count = await redis.get(`votes:${battleId}:${candidateId}`);
                voteCounts[candidateId] = parseInt(count) || 0;
            }

            return voteCounts;
        } catch (error) {
            logger.error('Get vote counts error:', error);
            throw error;
        }
    }

    /**
     * Get vote breakdown by type for a battle
     * @param {string} battleId - Battle ID
     * @param {string} candidateId - Candidate ID
     */
    async getVoteBreakdown(battleId, candidateId) {
        try {
            const { data, error } = await supabase
                .from('battle_votes')
                .select('vote_type, weight')
                .eq('battle_id', battleId)
                .eq('candidate_id', candidateId);

            if (error) throw error;

            const breakdown = {
                regular: 0,
                gift: 0,
                super: 0,
                total: 0
            };

            data.forEach(vote => {
                breakdown[vote.vote_type] = (breakdown[vote.vote_type] || 0) + vote.weight;
                breakdown.total += vote.weight;
            });

            return breakdown;
        } catch (error) {
            logger.error('Get vote breakdown error:', error);
            throw error;
        }
    }

    /**
     * Finalize votes and determine winner
     * @param {string} battleId - Battle ID
     * @param {Array<string>} candidateIds - List of candidate IDs
     */
    async finalizeVotes(battleId, candidateIds) {
        try {
            const voteCounts = await this.getVoteCounts(battleId, candidateIds);

            let winnerId = null;
            let maxVotes = 0;
            const results = {};

            candidateIds.forEach(candidateId => {
                const votes = voteCounts[candidateId] || 0;
                results[candidateId] = votes;

                if (votes > maxVotes) {
                    maxVotes = votes;
                    winnerId = candidateId;
                }
            });

            // Check for tie
            const tiedCandidates = candidateIds.filter(id => results[id] === maxVotes);
            const isTie = tiedCandidates.length > 1;

            return {
                winnerId: isTie ? null : winnerId,
                results,
                isTie,
                tiedCandidates: isTie ? tiedCandidates : []
            };
        } catch (error) {
            logger.error('Finalize votes error:', error);
            throw error;
        }
    }

    /**
     * Reset votes for a battle (for testing or restart)
     * @param {string} battleId - Battle ID
     * @param {Array<string>} candidateIds - List of candidate IDs
     */
    async resetVotes(battleId, candidateIds) {
        try {
            // Clear Redis vote counts
            const pipeline = redis.pipeline();
            candidateIds.forEach(candidateId => {
                pipeline.del(`votes:${battleId}:${candidateId}`);
            });
            await pipeline.exec();

            // Clear database votes
            const { error } = await supabase
                .from('battle_votes')
                .delete()
                .eq('battle_id', battleId);

            if (error) throw error;

            logger.info(`Votes reset for battle: ${battleId}`);
            return { success: true };
        } catch (error) {
            logger.error('Reset votes error:', error);
            throw error;
        }
    }

    /**
     * Get user's vote history for a battle
     * @param {string} battleId - Battle ID
     * @param {string} userId - User ID
     */
    async getUserVoteHistory(battleId, userId) {
        try {
            const { data, error } = await supabase
                .from('battle_votes')
                .select('*, candidates(*)')
                .eq('battle_id', battleId)
                .eq('voter_id', userId)
                .order('created_at', { ascending: false });

            if (error) throw error;

            return data || [];
        } catch (error) {
            logger.error('Get user vote history error:', error);
            throw error;
        }
    }

    /**
     * Stream vote updates via Redis pub/sub
     * @param {string} battleId - Battle ID
     * @param {Function} callback - Callback for vote updates
     */
    subscribeToVotes(battleId, callback) {
        const subscriber = redis.duplicate();
        subscriber.subscribe(`battle:${battleId}`, (err, count) => {
            if (err) {
                logger.error('Subscribe to votes error:', err);
                return;
            }
        });

        subscriber.on('message', (channel, message) => {
            if (channel === `battle:${battleId}`) {
                const data = JSON.parse(message);
                if (data.type === 'vote') {
                    callback(data.data);
                }
            }
        });

        return subscriber;
    }

    /**
     * Get battle leaderboard
     * @param {string} battleId - Battle ID
     * @param {Array<string>} candidateIds - List of candidate IDs
     * @param {number} limit - Number of top candidates to return
     */
    async getLeaderboard(battleId, candidateIds, limit = 10) {
        try {
            const voteCounts = await this.getVoteCounts(battleId, candidateIds);

            // Sort candidates by vote count
            const sorted = candidateIds
                .map(candidateId => ({
                    candidateId,
                    votes: voteCounts[candidateId] || 0
                }))
                .sort((a, b) => b.votes - a.votes)
                .slice(0, limit);

            return sorted;
        } catch (error) {
            logger.error('Get leaderboard error:', error);
            throw error;
        }
    }

    /**
     * Validate voting eligibility
     * @param {Object} params - Validation parameters
     * @param {string} params.userId - User ID
     * @param {string} params.battleId - Battle ID
     * @param {string} params.voteType - Type of vote
     */
    async validateVotingEligibility({ userId, battleId, voteType }) {
        try {
            // Check if user exists
            const { data: user } = await supabase
                .from('users')
                .select('id, is_banned')
                .eq('id', userId)
                .single();

            if (!user) {
                return { eligible: false, reason: 'User not found' };
            }

            if (user.is_banned) {
                return { eligible: false, reason: 'User is banned' };
            }

            // Check if battle exists and is active
            const { data: battle } = await supabase
                .from('live_battles')
                .select('status, started_at, ended_at')
                .eq('battle_id', battleId)
                .single();

            if (!battle) {
                return { eligible: false, reason: 'Battle not found' };
            }

            if (battle.status !== 'live' && battle.status !== 'voting') {
                return { eligible: false, reason: 'Battle is not accepting votes' };
            }

            // Check vote type specific rules
            if (voteType === 'gift' || voteType === 'super') {
                // Verify user has sufficient balance for weighted votes
                const { data: wallet } = await supabase
                    .from('wallets')
                    .select('coin_balance')
                    .eq('user_id', userId)
                    .single();

                if (!wallet || wallet.coin_balance <= 0) {
                    return { eligible: false, reason: 'Insufficient balance for weighted votes' };
                }
            }

            return { eligible: true };
        } catch (error) {
            logger.error('Validate voting eligibility error:', error);
            return { eligible: false, reason: 'Validation error' };
        }
    }
}

module.exports = new VotingService();