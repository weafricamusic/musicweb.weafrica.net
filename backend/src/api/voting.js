/**
 * Voting API Endpoints
 * 
 * REST endpoints for battle voting system
 */

const express = require('express');
const router = express.Router();
const votingService = require('../services/votingService');
const { authenticate } = require('../middleware/auth');

/**
 * POST /api/voting/vote
 * 
 * Cast a vote for a battle participant
 * 
 * Request body:
 *   - battleId: string - Battle ID
 *   - candidateId: string - Candidate being voted for
 *   - voteType: string (optional) - Type of vote: 'regular', 'gift', 'super'
 *   - weight: number (optional) - Vote weight (default: 1)
 */
router.post('/vote', authenticate, async (req, res) => {
    try {
        const { battleId, candidateId, voteType = 'regular', weight = 1 } = req.body;
        const voterId = req.user.id;

        if (!battleId || !candidateId) {
            return res.status(400).json({
                error: 'Missing parameters',
                message: 'battleId and candidateId are required'
            });
        }

        // Validate voting eligibility
        const eligibility = await votingService.validateVotingEligibility({
            userId: voterId,
            battleId,
            voteType
        });

        if (!eligibility.eligible) {
            return res.status(403).json({
                error: 'Not eligible to vote',
                message: eligibility.reason
            });
        }

        // Cast the vote
        const vote = await votingService.castVote({
            battleId,
            voterId,
            candidateId,
            voteType,
            weight
        });

        res.json({
            success: true,
            vote,
            message: 'Vote cast successfully'
        });

    } catch (error) {
        console.error('Vote endpoint error:', error);
        res.status(400).json({
            error: 'Vote failed',
            message: error.message
        });
    }
});

/**
 * GET /api/voting/battle/:battleId/results
 * 
 * Get current vote counts for a battle
 * 
 * Query parameters:
 *   - candidateIds: string[] - Comma-separated list of candidate IDs
 */
router.get('/battle/:battleId/results', async (req, res) => {
    try {
        const { battleId } = req.params;
        const { candidateIds } = req.query;

        if (!candidateIds) {
            return res.status(400).json({
                error: 'Missing candidateIds',
                message: 'candidateIds query parameter is required'
            });
        }

        const ids = Array.isArray(candidateIds) ? candidateIds : candidateIds.split(',');
        const voteCounts = await votingService.getVoteCounts(battleId, ids);

        res.json({
            battleId,
            voteCounts,
            timestamp: Date.now()
        });

    } catch (error) {
        console.error('Get results error:', error);
        res.status(500).json({
            error: 'Failed to get results',
            message: error.message
        });
    }
});

/**
 * GET /api/voting/battle/:battleId/breakdown
 * 
 * Get vote breakdown by type for a candidate
 * 
 * Query parameters:
 *   - candidateId: string - Candidate ID
 */
router.get('/battle/:battleId/breakdown', async (req, res) => {
    try {
        const { battleId } = req.params;
        const { candidateId } = req.query;

        if (!candidateId) {
            return res.status(400).json({
                error: 'Missing candidateId',
                message: 'candidateId query parameter is required'
            });
        }

        const breakdown = await votingService.getVoteBreakdown(battleId, candidateId);

        res.json({
            battleId,
            candidateId,
            breakdown,
            timestamp: Date.now()
        });

    } catch (error) {
        console.error('Get breakdown error:', error);
        res.status(500).json({
            error: 'Failed to get breakdown',
            message: error.message
        });
    }
});

/**
 * GET /api/voting/battle/:battleId/leaderboard
 * 
 * Get battle leaderboard
 * 
 * Query parameters:
 *   - candidateIds: string[] - Comma-separated list of candidate IDs
 *   - limit: number (optional) - Number of results (default: 10)
 */
router.get('/battle/:battleId/leaderboard', async (req, res) => {
    try {
        const { battleId } = req.params;
        const { candidateIds, limit = 10 } = req.query;

        if (!candidateIds) {
            return res.status(400).json({
                error: 'Missing candidateIds',
                message: 'candidateIds query parameter is required'
            });
        }

        const ids = Array.isArray(candidateIds) ? candidateIds : candidateIds.split(',');
        const leaderboard = await votingService.getLeaderboard(battleId, ids, parseInt(limit));

        res.json({
            battleId,
            leaderboard,
            timestamp: Date.now()
        });

    } catch (error) {
        console.error('Get leaderboard error:', error);
        res.status(500).json({
            error: 'Failed to get leaderboard',
            message: error.message
        });
    }
});

/**
 * GET /api/voting/battle/:battleId/finalize
 * 
 * Finalize votes and determine winner (admin only)
 */
router.get('/battle/:battleId/finalize', authenticate, async (req, res) => {
    try {
        const { battleId } = req.params;
        const { candidateIds } = req.query;

        // Check if user is admin
        if (!req.user.is_admin) {
            return res.status(403).json({
                error: 'Forbidden',
                message: 'Only admins can finalize votes'
            });
        }

        if (!candidateIds) {
            return res.status(400).json({
                error: 'Missing candidateIds',
                message: 'candidateIds query parameter is required'
            });
        }

        const ids = Array.isArray(candidateIds) ? candidateIds : candidateIds.split(',');
        const results = await votingService.finalizeVotes(battleId, ids);

        res.json({
            battleId,
            ...results,
            finalizedAt: new Date().toISOString()
        });

    } catch (error) {
        console.error('Finalize error:', error);
        res.status(500).json({
            error: 'Failed to finalize votes',
            message: error.message
        });
    }
});

/**
 * GET /api/voting/user/history
 * 
 * Get user's vote history for a battle
 * 
 * Query parameters:
 *   - battleId: string - Battle ID
 */
router.get('/user/history', authenticate, async (req, res) => {
    try {
        const { battleId } = req.query;
        const userId = req.user.id;

        if (!battleId) {
            return res.status(400).json({
                error: 'Missing battleId',
                message: 'battleId query parameter is required'
            });
        }

        const history = await votingService.getUserVoteHistory(battleId, userId);

        res.json({
            userId,
            battleId,
            history,
            totalVotes: history.length
        });

    } catch (error) {
        console.error('Get history error:', error);
        res.status(500).json({
            error: 'Failed to get vote history',
            message: error.message
        });
    }
});

/**
 * DELETE /api/voting/battle/:battleId/reset
 * 
 * Reset votes for a battle (admin only)
 */
router.delete('/battle/:battleId/reset', authenticate, async (req, res) => {
    try {
        const { battleId } = req.params;
        const { candidateIds } = req.query;

        // Check if user is admin
        if (!req.user.is_admin) {
            return res.status(403).json({
                error: 'Forbidden',
                message: 'Only admins can reset votes'
            });
        }

        if (!candidateIds) {
            return res.status(400).json({
                error: 'Missing candidateIds',
                message: 'candidateIds query parameter is required'
            });
        }

        const ids = Array.isArray(candidateIds) ? candidateIds : candidateIds.split(',');
        const result = await votingService.resetVotes(battleId, ids);

        res.json(result);

    } catch (error) {
        console.error('Reset error:', error);
        res.status(500).json({
            error: 'Failed to reset votes',
            message: error.message
        });
    }
});

/**
 * POST /api/voting/validate
 * 
 * Validate voting eligibility
 * 
 * Request body:
 *   - battleId: string - Battle ID
 *   - voteType: string (optional) - Type of vote
 */
router.post('/validate', authenticate, async (req, res) => {
    try {
        const { battleId, voteType = 'regular' } = req.body;
        const userId = req.user.id;

        if (!battleId) {
            return res.status(400).json({
                error: 'Missing battleId',
                message: 'battleId is required'
            });
        }

        const eligibility = await votingService.validateVotingEligibility({
            userId,
            battleId,
            voteType
        });

        res.json(eligibility);

    } catch (error) {
        console.error('Validate error:', error);
        res.status(500).json({
            error: 'Validation failed',
            message: error.message
        });
    }
});

module.exports = router;