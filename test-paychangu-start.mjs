#!/usr/bin/env node
/**
 * Test helper for the PayChangu start endpoint.
 *
 * Usage examples:
 *   node test-paychangu-start.mjs --base https://<ref>.functions.supabase.co --method POST --plan premium --user <uid> --months 1 --token <firebase_id_token>
 *   node test-paychangu-start.mjs --base https://<ref>.functions.supabase.co --method POST --plan artist_pro --user <uid> --months 1 --token <firebase_id_token>
 *   node test-paychangu-start.mjs --base https://<ref>.functions.supabase.co --method POST --plan dj_pro --user <uid> --months 1 --token <firebase_id_token>
 *   node test-paychangu-start.mjs --base https://<ref>.supabase.co/functions/v1 --method GET --plan premium --months 1 --token <firebase_id_token>
 */

function arg(name, fallback = undefined) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const v = process.argv[i + 1];
  if (!v || v.startsWith('--')) return '';
  return v;
}

function boolArg(name) {
  return process.argv.includes(`--${name}`);
}

const base = (arg('base', process.env.WEAFRICA_API_BASE || '') || '').replace(/\/+$/, '');
const method = (arg('method', 'POST') || 'POST').toUpperCase();
const planId = (arg('plan', arg('plan_id', 'premium')) || '').trim();
const userId = (arg('user', arg('user_id', '')) || '').trim();
const months = Number(arg('months', '1') || '1') || 1;
const countryCode = (arg('country', arg('country_code', 'MW')) || 'MW').trim().toUpperCase();
const token = (arg('token', process.env.FIREBASE_ID_TOKEN || '') || '').trim();
const path = (arg('path', '/api/paychangu/start') || '/api/paychangu/start').trim();
const verbose = boolArg('verbose');

if (!base) {
  console.error('Missing --base (e.g. https://<ref>.functions.supabase.co)');
  process.exit(2);
}

if (!planId) {
  console.error('Missing --plan');
  process.exit(2);
}

const headers = {
  'accept': 'application/json',
};
if (token) headers['authorization'] = `Bearer ${token}`;

let url;
let fetchOpts;

if (method === 'GET') {
  url = new URL(`${base}${path}`);
  url.searchParams.set('plan_id', planId);
  url.searchParams.set('months', String(months));
  url.searchParams.set('country_code', countryCode);
  if (userId) url.searchParams.set('user_id', userId);

  fetchOpts = { method: 'GET', headers };
} else if (method === 'POST') {
  url = new URL(`${base}${path}`);
  headers['content-type'] = 'application/json';

  const body = {
    plan_id: planId,
    months,
    interval_count: months,
    country_code: countryCode,
    ...(userId ? { user_id: userId } : {}),
  };

  fetchOpts = { method: 'POST', headers, body: JSON.stringify(body) };
} else {
  console.error('Invalid --method (use GET or POST)');
  process.exit(2);
}

if (verbose) {
  console.log('URL:', url.toString());
  console.log('Method:', fetchOpts.method);
  console.log('Auth:', token ? 'yes' : 'no');
}

const res = await fetch(url, fetchOpts);
const text = await res.text();

console.log('HTTP', res.status, res.statusText);
console.log('x-weafrica-build-tag:', res.headers.get('x-weafrica-build-tag') || '(missing)');
console.log('content-type:', res.headers.get('content-type') || '(missing)');
console.log(text);
