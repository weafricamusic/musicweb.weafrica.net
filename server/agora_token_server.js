// Minimal token and gift server for Agora (RTC + RTM)
// NOTE: Replace placeholder values and verify Agora REST endpoints per Agora docs before production.
const express = require('express');
const bodyParser = require('body-parser');
const axios = require('axios');
const { RtcTokenBuilder, RtcRole, RtmTokenBuilder, RtmRole } = require('agora-token');

const app = express();
app.use(bodyParser.json());

const APP_ID = process.env.APP_ID || '<YOUR_APP_ID>';
const APP_CERT = process.env.APP_CERT || '<YOUR_APP_CERT>';

function nowTs() { return Math.floor(Date.now() / 1000); }

app.get('/rtc-token', (req, res) => {
  const channel = req.query.channel;
  const uid = req.query.uid || '0';
  if (!channel) return res.status(400).json({ error: 'channel required' });
  const expireSecs = Number(req.query.expire) || 3600;
  const role = RtcRole.PUBLISHER;
  const privilegeExpireTs = nowTs() + expireSecs;
  try {
    const uidNum = /^\\d+$/.test(uid) ? Number(uid) : 0;
    const token = RtcTokenBuilder.buildTokenWithUid(APP_ID, APP_CERT, channel, uidNum, role, privilegeExpireTs);
    res.json({ token, expire: privilegeExpireTs });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/rtm-token', (req, res) => {
  const account = req.query.account;
  if (!account) return res.status(400).json({ error: 'account required' });
  const expireSecs = Number(req.query.expire) || 3600;
  try {
    const token = RtmTokenBuilder.buildToken(APP_ID, APP_CERT, account, RtmRole.LOGIN, expireSecs);
    res.json({ token, expire: nowTs() + expireSecs });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Helper: broadcast a confirmed gift to an Agora RTM channel via server-side push.
// IMPORTANT: Confirm the correct Agora REST endpoint and authentication method from Agora docs.
async function sendRtmChannelMessage(channel, messageJson) {
  // Placeholder implementation: many Agora accounts use the RTM REST API or a server SDK.
  // Consult https://docs.agora.io/ for the correct REST endpoint and required headers.
  // Example (replace with actual endpoint):
  const url = `https://api.agora.io/dev/v1/channel/${APP_ID}/${encodeURIComponent(channel)}/message`;
  const auth = Buffer.from(`${APP_ID}:${APP_CERT}`).toString('base64');
  try {
    const resp = await axios.post(url, { message: messageJson }, {
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      timeout: 5000,
    });
    return resp.data;
  } catch (e) {
    console.error('RTM push failed (placeholder):', e.message || e);
    throw e;
  }
}

app.post('/purchase-gift', async (req, res) => {
  const { buyerId, performerId, giftId, amount, channel } = req.body;
  if (!buyerId || !performerId || !giftId || !amount || !channel) return res.status(400).json({ error: 'missing fields' });

  // TODO: Validate buyer balance, deduct coins, persist transaction in DB.
  const confirmedGift = {
    type: 'gift',
    giftId,
    amount,
    from: buyerId,
    to: performerId,
    time: Date.now(),
  };

  // Attempt server-push to RTM channel (best-effort; errors don't block confirmation).
  try {
    await sendRtmChannelMessage(channel, JSON.stringify(confirmedGift));
    console.log('Broadcasted gift to channel', channel);
  } catch (e) {
    console.warn('Server-push failed; clients should still announce after confirmation.');
  }

  return res.json({ status: 'ok', gift: confirmedGift });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Agora token server running on :${PORT}`));
