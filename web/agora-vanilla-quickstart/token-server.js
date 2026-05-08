// ============================================================
// Agora Minimal Token Server (Node.js + Express)
//
// Purpose: Generate RTC tokens for clients. Reads credentials
// from environment variables. Do NOT hardcode certificates.
//
// Install dependencies:
//   npm install express dotenv agora-access-token
//
// Run:
//   AGORA_APP_ID=xxx AGORA_APP_CERT=xxx node token-server.js
// ============================================================

require('dotenv').config();

const express = require('express');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const app = express();

// Parse JSON bodies (for POST /token)
app.use(express.json());

// CORS - allow all for quickstart demo (restrict in production!)
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.header('Access-Control-Allow-Credentials', 'true');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    next();
});

const APP_ID = process.env.AGORA_APP_ID;
const APP_CERT = process.env.AGORA_APP_CERT;

// Check for missing credentials first
if (!APP_ID || !APP_CERT) {
    console.error('ERROR: Set AGORA_APP_ID and AGORA_APP_CERT environment variables.');
    console.error('Create a .env file in this directory with:');
    console.error('  AGORA_APP_ID=your_app_id');
    console.error('  AGORA_APP_CERT=your_app_certificate');
    process.exit(1);
}

// Then check for placeholder values (safe to call methods now that we know they exist)
const isPlaceholder =
    APP_ID.toLowerCase().includes('your') ||
    APP_CERT.toLowerCase().includes('your') ||
    APP_CERT.toLowerCase().includes('fake') ||
    APP_CERT.length < 20;

if (isPlaceholder) {
    console.error('\n=================================================================');
    console.error('WARNING: You are using placeholder credentials in your .env file.');
    console.error('Replace AGORA_APP_ID and AGORA_APP_CERT with real values');
    console.error('from your Agora console: https://console.agora.io');
    console.error('=================================================================\n');
    process.exit(1);
}

// ------------------------------------------------------------
// GET /rtc/:channel/:uid/:role
// Quick endpoint used by the vanilla HTML quickstart.
// role = 'publisher' (host) or 'subscriber' (audience)
// ------------------------------------------------------------
app.get('/rtc/:channel/:uid/:role', (req, res) => {
    const channel = req.params.channel;
    const uid = Number(req.params.uid);
    const roleParam = req.params.role; // 'publisher' or 'subscriber'
    const role = roleParam === 'publisher' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;

    const expirationInSeconds = 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + expirationInSeconds;

    try {
        const token = RtcTokenBuilder.buildTokenWithUid(
            APP_ID,
            APP_CERT,
            channel,
            uid,
            role,
            privilegeExpire
        );
        res.type('text/plain').send(token);
    } catch (e) {
        console.error('Token generation error:', e);
        res.status(500).json({ error: e.message || String(e) });
    }
});

// ------------------------------------------------------------
// POST /token
// Flexible JSON endpoint. Body:
//   { channelName, role: "publisher"|"subscriber", uid, ttlSeconds? }
// ------------------------------------------------------------
app.post('/token', (req, res) => {
    const {
        channelName,
        role = 'subscriber',
        uid = 0,
        ttlSeconds = 3600,
    } = req.body;

    if (!channelName || typeof channelName !== 'string' || channelName.trim() === '') {
        return res.status(400).json({ error: 'channelName is required and must be a non-empty string' });
    }

    const rtcRole =
        role === 'publisher' || role === 'broadcaster' || role === 'host'
            ? RtcRole.PUBLISHER
            : RtcRole.SUBSCRIBER;

    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + Number(ttlSeconds || 3600);

    try {
        const token = RtcTokenBuilder.buildTokenWithUid(
            APP_ID,
            APP_CERT,
            channelName.trim(),
            Number(uid),
            rtcRole,
            privilegeExpire
        );
        res.json({
            token,
            appId: APP_ID,
            channel: channelName.trim(),
            uid: Number(uid),
            role: rtcRole === RtcRole.PUBLISHER ? 'publisher' : 'subscriber',
            expiresAt: new Date(privilegeExpire * 1000).toISOString(),
        });
    } catch (e) {
        console.error('Token generation error:', e);
        res.status(500).json({ error: e.message || String(e) });
    }
});

// GET /token — informational only (POST is the real endpoint)
app.get('/token', (_req, res) => {
    res.json({
        note: 'Use POST /token with a JSON body, or GET /rtc/:channel/:uid/:role',
        postExample: {
            method: 'POST',
            url: '/token',
            body: {
                channelName: 'myChannel',
                role: 'publisher', // or 'subscriber'
                uid: 12345,
                ttlSeconds: 3600,
            },
        },
        getExample: 'GET /rtc/myChannel/12345/publisher',
    });
});

// Health check
app.get('/', (_req, res) => {
    res.json({
        status: 'Agora token server running',
        appId: APP_ID,
        endpoints: {
            getRtcToken: '/rtc/:channel/:uid/:role',
            postToken: '/token',
            tokenDocs: '/token',
        },
    });
});

const PORT = process.env.PORT || 3000;
// Bind to 0.0.0.0 so other devices on your network can reach the server
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Token server running on port ${PORT}`);
    console.log(`GET  http://localhost:${PORT}/rtc/:channel/:uid/:role`);
    console.log(`POST http://localhost:${PORT}/token`);
    console.log(`     (accessible from any device on your network)`);
});
