const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Coin packages
const COIN_PACKAGES = [
  { id: 'coins_100', title: '100 Coins', coins: 100, price: 0.99, bonus: 0 },
  { id: 'coins_500', title: '500 Coins', coins: 500, price: 4.49, bonus: 0 },
  { id: 'coins_1000', title: '1000 Coins', coins: 1000, price: 7.99, bonus: 0 },
  { id: 'coins_5000', title: '5000 Coins', coins: 5000, price: 34.99, bonus: 0 }
];

// Get coin packages
router.get('/packages', (req, res) => {
  res.json(COIN_PACKAGES);
});

function normalizePayChanguSecret() {
  return String(process.env.PAYCHANGU_SECRET_KEY || process.env.PAYCHANGU_SECRET || '').trim();
}

function normalizeCurrency() {
  const c = String(process.env.PAYCHANGU_CURRENCY || 'USD').trim().toUpperCase();
  return c || 'USD';
}

function normalizeCallbackUrl() {
  return (
    String(process.env.PAYCHANGU_CALLBACK_URL || '').trim() ||
    String(process.env.PAYCHANGU_IPN_URL || '').trim() ||
    `${String(process.env.FRONTEND_URL || '').replace(/\/$/, '')}/payment/callback`
  );
}

function normalizeReturnUrl() {
  return (
    String(process.env.PAYCHANGU_RETURN_URL || '').trim() ||
    `${String(process.env.FRONTEND_URL || '').replace(/\/$/, '')}/payment/success`
  );
}

function isVerifySuccess(payload) {
  const status = String(payload?.status || '').toLowerCase();
  const txStatus = String(payload?.data?.status || '').toLowerCase();
  return (
    status === 'success' &&
    ['successful', 'success', 'paid', 'completed'].includes(txStatus)
  );
}

async function ensureWalletCredit(userId, coinsToAdd) {
  const { data: existing } = await supabase
    .from('wallets')
    .select('coin_balance,total_coins_earned')
    .eq('user_id', userId)
    .maybeSingle();

  const currentBalance = Number(existing?.coin_balance || 0);
  const currentEarned = Number(existing?.total_coins_earned || 0);

  const payload = {
    user_id: userId,
    coin_balance: currentBalance + coinsToAdd,
    total_coins_earned: currentEarned + coinsToAdd,
    updated_at: new Date().toISOString(),
    last_transaction_at: new Date().toISOString(),
  };

  const { error } = await supabase
    .from('wallets')
    .upsert(payload, { onConflict: 'user_id' });

  if (error) throw error;
}

async function createPayChanguCheckout(req, res) {
  try {
    const { packageId } = req.body;
    const pkg = COIN_PACKAGES.find(p => p.id === packageId);
    const secret = normalizePayChanguSecret();

    if (!pkg) {
      return res.status(400).json({ error: 'Invalid package' });
    }
    if (!secret) {
      return res.status(503).json({ error: 'Missing PAYCHANGU_SECRET_KEY' });
    }

    const txRef = `weafrica-coins-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

    const payload = {
      amount: Number(pkg.price),
      currency: normalizeCurrency(),
      callback_url: normalizeCallbackUrl(),
      return_url: normalizeReturnUrl(),
      tx_ref: txRef,
      email: req.user.email || 'customer@weafrica.app',
      first_name: req.user.displayName || req.user.username || 'WeAfrica',
      last_name: 'User',
      customization: {
        title: 'WeAfrica Music - Coin Purchase',
        description: `Purchase ${pkg.coins + pkg.bonus} coins`,
      },
      meta: {
        purpose: 'coin_topup',
        uid: req.user.id,
        package_id: pkg.id,
        coins: pkg.coins + pkg.bonus,
      },
    };

    const pgRes = await fetch('https://api.paychangu.com/payment', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${secret}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const pgJson = await pgRes.json().catch(() => ({}));
    const checkoutUrl = String(pgJson?.data?.checkout_url || '').trim();

    if (!pgRes.ok || !checkoutUrl) {
      return res.status(502).json({
        error: 'Failed to initiate PayChangu transaction.',
        details: pgJson,
      });
    }

    // Track pending transaction for audit/history.
    await supabase.from('transactions').insert({
      user_id: req.user.id,
      type: 'purchase',
      amount: pkg.coins + pkg.bonus,
      currency: 'coins',
      status: 'pending',
      price: Number(pkg.price),
      metadata: { provider: 'paychangu', txRef, packageId: pkg.id },
      created_at: new Date().toISOString(),
    });

    res.json({
      provider: 'paychangu',
      checkout_url: checkoutUrl,
      tx_ref: txRef,
    });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Payment start failed' });
  }
}

async function verifyPayChanguCheckout(req, res) {
  try {
    const txRef = String(req.body?.tx_ref || req.body?.provider_reference || '').trim();
    if (!txRef) {
      return res.status(400).json({ error: 'Missing tx_ref' });
    }

    const { data: txRows, error: txLookupError } = await supabase
      .from('transactions')
      .select('id,status,metadata')
      .eq('user_id', req.user.id)
      .contains('metadata', { txRef })
      .order('created_at', { ascending: false })
      .limit(1);

    if (txLookupError) {
      return res.status(500).json({ error: txLookupError.message });
    }

    const txRow = Array.isArray(txRows) && txRows.length > 0 ? txRows[0] : null;
    if (!txRow) {
      return res.status(403).json({ error: 'Forbidden tx_ref' });
    }

    const packageId = String(txRow?.metadata?.packageId || '').trim();
    const pkg = COIN_PACKAGES.find(p => p.id === packageId);
    if (!pkg) {
      return res.status(400).json({ error: 'Unknown package for tx_ref' });
    }

    if (String(txRow.status || '').toLowerCase() === 'completed') {
      return res.json({ ok: true, processed: true, success: true, idempotent: true, tx_ref: txRef });
    }

    const secret = normalizePayChanguSecret();
    if (!secret) {
      return res.status(503).json({ error: 'Missing PAYCHANGU_SECRET_KEY' });
    }

    const verifyRes = await fetch(
      `https://api.paychangu.com/verify-payment/${encodeURIComponent(txRef)}`,
      {
        method: 'GET',
        headers: {
          authorization: `Bearer ${secret}`,
          accept: 'application/json',
        },
      }
    );

    const verified = await verifyRes.json().catch(() => ({}));
    const success = verifyRes.ok && isVerifySuccess(verified);
    if (!success) {
      return res.json({ ok: true, processed: true, success: false, tx_ref: txRef });
    }

    const coins = pkg.coins + pkg.bonus;
    await ensureWalletCredit(req.user.id, coins);

    const { error: markErr } = await supabase
      .from('transactions')
      .update({ status: 'completed', completed_at: new Date().toISOString() })
      .eq('id', txRow.id);

    if (markErr) {
      return res.status(500).json({ error: markErr.message });
    }

    res.json({ ok: true, processed: true, success: true, tx_ref: txRef });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Payment verify failed' });
  }
}

// Canonical PayChangu routes.
router.post('/paychangu/start', authenticate, createPayChanguCheckout);
router.post('/paychangu/verify', authenticate, verifyPayChanguCheckout);
router.post('/payments/paychangu/start', authenticate, createPayChanguCheckout);
router.post('/payments/paychangu/verify', authenticate, verifyPayChanguCheckout);
router.post('/coins/paychangu/start', authenticate, createPayChanguCheckout);
router.post('/coins/paychangu/verify', authenticate, verifyPayChanguCheckout);

// Backward-compatible aliases for legacy clients.
router.post('/flutterwave', authenticate, createPayChanguCheckout);
router.post('/stripe', authenticate, createPayChanguCheckout);

// Keep webhook paths for clients still configured, but mark as legacy/no-op.
router.post('/stripe/webhook', (_req, res) => {
  res.status(410).json({
    ok: false,
    message: 'Stripe webhook is deprecated. Use /api/payments/paychangu/verify and PayChangu webhook integration.',
  });
});

router.post('/flutterwave/webhook', (_req, res) => {
  res.status(410).json({
    ok: false,
    message: 'Flutterwave webhook is deprecated. Use /api/payments/paychangu/verify and PayChangu webhook integration.',
  });
});

// Get transaction history
router.get('/transactions', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('transactions')
      .select('*')
      .eq('user_id', req.user.id)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;