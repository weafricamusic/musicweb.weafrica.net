/**
 * Agora Token Generation API
 * 
 * This module handles token generation for Agora RTC and RTM.
 * Tokens are short-lived and should be generated server-side
 * using the App Certificate.
 */

const express = require('express');
const router = express.Router();
const { RtcTokenBuilder, RtcRole, RtmTokenBuilder } = require('agora-token');

// Configuration from environment variables
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;

// Token expiration time in seconds (default: 24 hours)
const TOKEN_EXPIRATION = parseInt(process.env.AGORA_TOKEN_EXPIRATION) || 86400;

/**
 * Middleware to validate Agora configuration
 */
function validateAgoraConfig(req, res, next) {
    if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
        return res.status(500).json({
            error: 'Agora credentials not configured',
            message: 'AGORA_APP_ID and AGORA_APP_CERTIFICATE must be set in environment variables'
        });
    }
    next();
}

/**
 * POST /api/agora/tokens
 * 
 * Generate RTC and RTM tokens for a user joining a channel.
 * 
 * Request body:
 *   - channelName: string - The channel name (match ID)
 *   - role: string - 'host' or 'audience' (default: 'audience')
 *   - uid: number (optional) - Specific UID, or null to let Agora assign
 * 
 * Response:
 *   - rtcToken: string - Token for RTC (audio/video)
 *   - rtmToken: string - Token for RTM (messaging)
 *   - appId: string - Agora App ID
 *   - channel: string - Channel name
 *   - uid: number - Assigned or requested UID
 *   - role: string - User role
 */
router.post('/tokens', validateAgoraConfig, async (req, res) => {
    try {
        const { channelName, role = 'audience', uid: requestedUid } = req.body;

        if (!channelName) {
            return res.status(400).json({
                error: 'Missing channelName',
                message: 'Channel name is required'
            });
        }

        // Determine RTC role
        const rtcRole = role === 'host' ? RtcRole.HOST : RtcRole.AUDIENCE;

        // Generate UID if not provided
        const uid = requestedUid || Math.floor(Math.random() * (100000 - 1)) + 1;

        // Calculate expiration timestamp
        const expirationTime = Math.floor(Date.now() / 1000) + TOKEN_EXPIRATION;

        // Generate RTC token
        const rtcToken = RtcTokenBuilder.buildTokenWithUid(
            AGORA_APP_ID,
            AGORA_APP_CERTIFICATE,
            channelName,
            uid,
            rtcRole,
            expirationTime
        );

        // Generate RTM token
        const rtmToken = RtmTokenBuilder.buildTokenWithUid(
            AGORA_APP_ID,
            AGORA_APP_CERTIFICATE,
            uid.toString(),
            expirationTime
        );

        console.log(`Token generated: channel=${channelName}, uid=${uid}, role=${role}`);

        res.json({
            rtcToken,
            rtmToken,
            appId: AGORA_APP_ID,
            channel: channelName,
            uid,
            role,
            expiresAt: new Date(expirationTime * 1000).toISOString()
        });

    } catch (error) {
        console.error('Error generating Agora tokens:', error);
        res.status(500).json({
            error: 'Token generation failed',
            message: error.message
        });
    }
});

/**
 * POST /api/agora/tokens/rtm
 * 
 * Generate RTM-only token for messaging without RTC.
 * Useful for spectators who only need chat functionality.
 */
router.post('/tokens/rtm', validateAgoraConfig, async (req, res) => {
    try {
        const { uid: requestedUid } = req.body;
        const uid = requestedUid || Math.floor(Math.random() * (100000 - 1)) + 1;
        const expirationTime = Math.floor(Date.now() / 1000) + TOKEN_EXPIRATION;

        const rtmToken = RtmTokenBuilder.buildTokenWithUid(
            AGORA_APP_ID,
            AGORA_APP_CERTIFICATE,
            uid.toString(),
            expirationTime
        );

        res.json({
            rtmToken,
            appId: AGORA_APP_ID,
            uid,
            expiresAt: new Date(expirationTime * 1000).toISOString()
        });

    } catch (error) {
        console.error('Error generating RTM token:', error);
        res.status(500).json({
            error: 'RTM token generation failed',
            message: error.message
        });
    }
});

/**
 * POST /api/agora/tokens/rtc
 * 
 * Generate RTC-only token for audio/video without RTM.
 */
router.post('/tokens/rtc', validateAgoraConfig, async (req, res) => {
    try {
        const { channelName, role = 'audience', uid: requestedUid } = req.body;

        if (!channelName) {
            return res.status(400).json({
                error: 'Missing channelName',
                message: 'Channel name is required'
            });
        }

        const rtcRole = role === 'host' ? RtcRole.HOST : RtcRole.AUDIENCE;
        const uid = requestedUid || Math.floor(Math.random() * (100000 - 1)) + 1;
        const expirationTime = Math.floor(Date.now() / 1000) + TOKEN_EXPIRATION;

        const rtcToken = RtcTokenBuilder.buildTokenWithUid(
            AGORA_APP_ID,
            AGORA_APP_CERTIFICATE,
            channelName,
            uid,
            rtcRole,
            expirationTime
        );

        res.json({
            rtcToken,
            appId: AGORA_APP_ID,
            channel: channelName,
            uid,
            role,
            expiresAt: new Date(expirationTime * 1000).toISOString()
        });

    } catch (error) {
        console.error('Error generating RTC token:', error);
        res.status(500).json({
            error: 'RTC token generation failed',
            message: error.message
        });
    }
});

/**
 * GET /api/agora/config
 * 
 * Get public Agora configuration (App ID only).
 * This endpoint doesn't require authentication.
 */
router.get('/config', (req, res) => {
    res.json({
        appId: AGORA_APP_ID || null,
        configured: !!(AGORA_APP_ID && AGORA_APP_CERTIFICATE)
    });
});

/**
 * POST /api/agora/recording/start
 * 
 * Start cloud recording for a channel.
 * This would integrate with Agora Cloud Recording API.
 */
router.post('/recording/start', validateAgoraConfig, async (req, res) => {
    try {
        const { channelName, resourceId } = req.body;

        if (!channelName) {
            return res.status(400).json({
                error: 'Missing channelName',
                message: 'Channel name is required'
            });
        }

        // TODO: Implement Agora Cloud Recording API integration
        // This would involve:
        // 1. Acquiring a resource
        // 2. Starting the recording
        // 3. Storing the recording ID for later retrieval

        console.log(`Recording start requested for channel: ${channelName}`);

        res.json({
            message: 'Cloud recording start requested',
            channel: channelName,
            // recordingId: result.sid,
            // resourceId: result.resourceId,
        });

    } catch (error) {
        console.error('Error starting cloud recording:', error);
        res.status(500).json({
            error: 'Cloud recording start failed',
            message: error.message
        });
    }
});

/**
 * POST /api/agora/recording/stop
 * 
 * Stop cloud recording for a channel.
 */
router.post('/recording/stop', validateAgoraConfig, async (req, res) => {
    try {
        const { channelName, resourceId, recordingId } = req.body;

        if (!channelName || !recordingId) {
            return res.status(400).json({
                error: 'Missing parameters',
                message: 'Channel name and recording ID are required'
            });
        }

        // TODO: Implement Agora Cloud Recording API integration
        // This would involve stopping the recording and getting the file URLs

        console.log(`Recording stop requested for channel: ${channelName}, recording: ${recordingId}`);

        res.json({
            message: 'Cloud recording stop requested',
            channel: channelName,
            recordingId,
        });

    } catch (error) {
        console.error('Error stopping cloud recording:', error);
        res.status(500).json({
            error: 'Cloud recording stop failed',
            message: error.message
        });
    }
});

module.exports = router;