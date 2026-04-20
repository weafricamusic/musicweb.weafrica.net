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

async function restSelect(baseUrl, apiKey, table, select, extraQuery = '') {
  const url = new URL(`${baseUrl}/rest/v1/${table}`);
  url.searchParams.set('select', select);
  url.searchParams.set('limit', '1');
  if (extraQuery) {
    const extra = new URLSearchParams(extraQuery);
    for (const [key, value] of extra.entries()) url.searchParams.set(key, value);
  }

  const res = await fetch(url, {
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${apiKey}`,
      Accept: 'application/json',
    },
  });

  const text = await res.text();
  return {
    ok: res.ok,
    status: res.status,
    url: url.toString(),
    body: text,
  };
}

async function main() {
  const envPath = arg('env', 'tool/supabase.env.json');
  const env = await loadEnvJson(envPath);
  const supabaseUrl = String(env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
  const apiKey = String(env.SUPABASE_ANON_KEY ?? env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();

  if (!supabaseUrl || !apiKey) {
    throw new Error(`Missing SUPABASE_URL or SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY in ${envPath}`);
  }

  const checks = [
    {
      label: 'subscription_plans',
      table: 'subscription_plans',
      select: 'plan_id,audience,name,price_mwk,billing_interval,currency,active,is_active,sort_order,features,perks,marketing',
    },
    {
      label: 'promotions',
      table: 'promotions',
      select: 'id,title,target_plan,target_plans,deep_link,is_active',
    },
    {
      label: 'coins',
      table: 'coins',
      select: 'code,name,value_mwk,coin_amount,usd_reference_price,sort_order,status',
    },
    {
      label: 'coin_packages',
      table: 'coin_packages',
      select: 'id,title,coins,bonus_coins,price,currency,active,sort_order',
    },
  ];

  let failed = false;
  for (const check of checks) {
    const result = await restSelect(supabaseUrl, apiKey, check.table, check.select);
    const prefix = `${check.label}: HTTP ${result.status}`;
    if (!result.ok) {
      failed = true;
      console.error(`${prefix} ❌`);
      console.error(result.url);
      console.error(result.body);
      continue;
    }

    console.log(`${prefix} ✅`);
    console.log(result.url);
    console.log(result.body.slice(0, 400));
  }

  if (failed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
