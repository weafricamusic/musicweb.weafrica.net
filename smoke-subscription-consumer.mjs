#!/usr/bin/env node
/**
 * Smoke the public subscription catalog.
 *
 * Examples:
 *   node smoke-subscription-consumer.mjs --base https://<ref>.functions.supabase.co --audience consumer
 *   node smoke-subscription-consumer.mjs --base https://<ref>.functions.supabase.co --audience artist
 *   node smoke-subscription-consumer.mjs --base https://<ref>.functions.supabase.co --audience dj
 */

function arg(name, fallback = '') {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  return process.argv[i + 1] ?? fallback;
}

const base = (arg('base', process.env.WEAFRICA_API_BASE || process.env.WEAFRICA_API_BASE_URL || '') || '').replace(/\/+$/, '');
const audience = (arg('audience', 'consumer') || 'consumer').trim().toLowerCase();

if (!base) {
  console.error('Missing --base (or WEAFRICA_API_BASE / WEAFRICA_API_BASE_URL)');
  process.exit(2);
}

const url = new URL(`${base}/api/subscriptions/plans`);
url.searchParams.set('audience', audience);

const res = await fetch(url, { headers: { accept: 'application/json' } });
const text = await res.text();
console.log('HTTP', res.status, res.statusText);
if (!res.ok) {
  console.log(text);
  process.exit(1);
}

const payload = JSON.parse(text);
const plans = Array.isArray(payload) ? payload : Array.isArray(payload?.plans) ? payload.plans : [];
console.log('source:', payload?.source ?? '(unknown)');
for (const plan of plans) {
  console.log([
    plan.plan_id ?? plan.id ?? '',
    plan.name ?? '',
    plan.price_mwk ?? plan.price ?? '',
    plan.billing_interval ?? plan.interval ?? '',
  ].join(' | '));
}
