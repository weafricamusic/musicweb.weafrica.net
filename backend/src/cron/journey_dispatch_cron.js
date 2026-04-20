const cron = require('node-cron');
const axios = require('axios');

async function dispatchOnce() {
  const url = String(process.env.WEAFRICA_JOURNEY_DISPATCH_URL || '').trim();
  const token = String(process.env.WEAFRICA_JOURNEY_CRON_TOKEN || '').trim();

  if (!url || !token) {
    console.warn('[journey-cron] Missing WEAFRICA_JOURNEY_DISPATCH_URL or WEAFRICA_JOURNEY_CRON_TOKEN');
    return;
  }

  try {
    const res = await axios.post(
      url,
      { max: 50 },
      {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-debug-token': token,
        },
        timeout: 15_000,
        validateStatus: () => true,
      },
    );

    const text = typeof res.data === 'string' ? res.data : JSON.stringify(res.data);
    if (res.status < 200 || res.status >= 300) {
      console.warn(`[journey-cron] Dispatch failed HTTP ${res.status}: ${text.slice(0, 500)}`);
      return;
    }

    console.log(`[journey-cron] Dispatch ok: ${text.slice(0, 500)}`);
  } catch (e) {
    console.warn('[journey-cron] Dispatch error:', e);
  }
}

function startJourneyDispatchCron() {
  const enabled = String(process.env.WEAFRICA_JOURNEY_CRON_ENABLED || '').trim().toLowerCase() === 'true';
  if (!enabled) return;

  // Every minute.
  cron.schedule('* * * * *', () => {
    void dispatchOnce();
  });

  console.log('[journey-cron] Enabled (runs every minute)');
}

module.exports = {
  startJourneyDispatchCron,
};
