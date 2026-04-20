#!/usr/bin/env node
import { readFile } from 'node:fs/promises';

function arg(name, fallback = '') {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  return process.argv[i + 1] ?? fallback;
}

async function loadEnvJson(filePath) {
  const raw = await readFile(filePath, 'utf8');
  const decoded = JSON.parse(raw);
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new Error(`Invalid JSON object in ${filePath}`);
  }
  return decoded;
}

async function restList(baseUrl, apiKey, table, select, query = {}) {
  const url = new URL(`${baseUrl}/rest/v1/${table}`);
  url.searchParams.set('select', select);
  for (const [key, value] of Object.entries(query)) {
    if (value != null && value !== '') url.searchParams.set(key, String(value));
  }

  const res = await fetch(url, {
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${apiKey}`,
      Accept: 'application/json',
    },
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${table} request failed (${res.status}): ${text}`);
  }
  return JSON.parse(text);
}

function fail(message) {
  console.error(`❌ ${message}`);
  process.exitCode = 1;
}

function pass(message) {
  console.log(`✅ ${message}`);
}

async function main() {
  const envPath = arg('env', 'tool/supabase.env.json');
  const env = await loadEnvJson(envPath);
  const supabaseUrl = String(env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
  const apiKey = String(env.SUPABASE_ANON_KEY ?? env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();

  if (!supabaseUrl || !apiKey) {
    throw new Error(`Missing SUPABASE_URL or SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY in ${envPath}`);
  }

  const rows = await restList(
    supabaseUrl,
    apiKey,
    'subscription_plans',
    'plan_id,audience,name,price_mwk,billing_interval,active,is_active,sort_order',
    { order: 'sort_order.asc' },
  );

  const byAudience = new Map();
  for (const row of rows) {
    const audience = String(row.audience ?? 'unknown');
    if (!byAudience.has(audience)) byAudience.set(audience, []);
    byAudience.get(audience).push(row);
  }

  const expected = {
    consumer: ['free', 'premium', 'platinum'],
    artist: ['artist_starter', 'artist_pro', 'artist_premium'],
    dj: ['dj_starter', 'dj_pro', 'dj_premium'],
  };

  for (const [audience, ids] of Object.entries(expected)) {
    const active = (byAudience.get(audience) ?? []).filter((row) => row.active !== false && row.is_active !== false);
    const activeIds = active
      .filter((row) => ['month', 'monthly', ''].includes(String(row.billing_interval ?? '').toLowerCase()))
      .map((row) => String(row.plan_id));
    const missing = ids.filter((id) => !activeIds.includes(id));
    if (missing.length > 0) {
      fail(`${audience} missing launch plans: ${missing.join(', ')}`);
    } else {
      pass(`${audience} launch plans present: ${ids.join(', ')}`);
    }
  }

  const legacyRows = rows.filter((row) => {
    const id = String(row.plan_id ?? '');
    return ['family', 'starter', 'pro', 'elite', 'premium_weekly', 'platinum_weekly', 'pro_weekly', 'elite_weekly', 'vip'].includes(id);
  });
  const activeLegacy = legacyRows.filter((row) => row.active !== false && row.is_active !== false);
  if (activeLegacy.length > 0) {
    fail(`Legacy rows are still active: ${activeLegacy.map((row) => row.plan_id).join(', ')}`);
  } else {
    pass('Legacy subscription rows are inactive');
  }

  const coins = await restList(
    supabaseUrl,
    apiKey,
    'coins',
    'code,name,value_mwk,coin_amount,usd_reference_price,sort_order,status',
    { order: 'sort_order.asc' },
  );
  const activeCoins = coins.filter((row) => String(row.status ?? 'active') === 'active');
  const expectedCoinCodes = ['coins_100', 'coins_500', 'coins_1000', 'coins_5000'];
  const missingCoinCodes = expectedCoinCodes.filter((code) => !activeCoins.some((row) => row.code === code));
  if (missingCoinCodes.length > 0) {
    fail(`Missing active coin packs: ${missingCoinCodes.join(', ')}`);
  } else {
    pass(`Coin packs present: ${expectedCoinCodes.join(', ')}`);
  }

  const coinPackages = await restList(
    supabaseUrl,
    apiKey,
    'coin_packages',
    'id,title,coins,bonus_coins,price,currency,active,sort_order',
    { order: 'sort_order.asc' },
  );
  const activePackages = coinPackages.filter((row) => row.active !== false).map((row) => String(row.id));
  const missingPackages = expectedCoinCodes.filter((id) => !activePackages.includes(id));
  if (missingPackages.length > 0) {
    fail(`Missing active checkout coin packages: ${missingPackages.join(', ')}`);
  } else {
    pass(`Checkout coin packages present: ${expectedCoinCodes.join(', ')}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
