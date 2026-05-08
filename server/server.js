// Node/Express Agora token server + server-push gift endpoint (demo)
// Security: APP_CERT must remain server-side. Use real auth and DB in production.
require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const axios = require('axios');
const { RtcTokenBuilder, RtcRole, RtmTokenBuilder, RtmRole } = require('agora-token');

const APP_ID = process.env.APP_ID || '<YOUR_APP_ID>';
const APP_CERT = process.env.APP_CERT || '<YOUR_APP_CERT>';
const DEMO_API_KEY = process.env.DEMO_API_KEY || 'demo-api-key';

const app = express();
app.use(bodyParser.json());

function nowTs() { return Math.floor(Date.now() / 1000); }

// Simple in-memory demo store (replace with real DB)
const users = {
  'buyer1': { balance: 1000 },
  'performer1': { balance: 0 },
};
const transactions = [];

function requireAuth(req, res, next) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Bearer ')) return res.status(401).json({ error: 'missing bearer token' });
  const token = h.substring(7);
  if (token !== DEMO_API_KEY) return res.status(403).json({ error: 'invalid api key' });
  next();
}

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

// Helper: publish a message to Agora RTM channel via REST API (placeholder endpoint)
// NOTE: Verify the correct RTM REST publish endpoint for your Agora account per docs.
async function publishRtmChannelMessage(channel, message) {
  const url = `https://api.agora.io/dev/v1/channel/${APP_ID}/${encodeURIComponent(channel)}/message`;
  const auth = Buffer.from(`${APP_ID}:${APP_CERT}`).toString('base64');
  const payload = { message: { text: message } };
  return axios.post(url, payload, {
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    timeout: 5000,
  });
}

app.post('/purchase-gift', requireAuth, async (req, res) => {
  const { buyerId, performerId, giftId, amount, channel } = req.body;
  if (!buyerId || !performerId || !giftId || !amount || !channel) return res.status(400).json({ error: 'missing fields' });

  // Validate buyer exists
  const buyer = users[buyerId];
  if (!buyer) return res.status(404).json({ error: 'buyer not found' });
  if (buyer.balance < amount) return res.status(400).json({ error: 'insufficient funds' });

  // Deduct and record transaction
  buyer.balance -= amount;
  const tx = { id: transactions.length + 1, buyerId, performerId, giftId, amount, time: Date.now() };
  transactions.push(tx);

  const confirmedGift = {
    type: 'gift',
    giftId,
    amount,
    from: buyerId,
    to: performerId,
    txId: tx.id,
    time: tx.time,
  };

  // Server-push via Agora RTM REST (best-effort)
  try {
    await publishRtmChannelMessage(channel, JSON.stringify(confirmedGift));
    console.log('Published gift to channel', channel);
  } catch (e) {
    console.warn('RTM publish failed (demo):', e.message || e);
  }

  return res.json({ status: 'ok', gift: confirmedGift });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Agora token & gift server running on :${PORT}`));
