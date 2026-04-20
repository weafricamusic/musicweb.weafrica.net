#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

function readText(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

function readEnvFromFile(relativePath, name) {
  const text = readText(relativePath);
  const match = text.match(new RegExp(`^${name}=(.*)$`, 'm'));
  if (!match) {
    throw new Error(`${name} missing from ${relativePath}`);
  }
  return match[1].trim().replace(/^"|"$/g, '');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForPort(host, port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ok = await new Promise((resolve) => {
      const socket = net.createConnection({ host, port });
      socket.once('connect', () => {
        socket.end();
        resolve(true);
      });
      socket.once('error', () => resolve(false));
      socket.setTimeout(500, () => {
        socket.destroy();
        resolve(false);
      });
    });

    if (ok) return;
    await sleep(250);
  }
  throw new Error(`Timeout waiting for ${host}:${port}`);
}

async function requestJson(url, init) {
  const response = await fetch(url, init);
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { raw: text };
  }
  return { status: response.status, ok: response.ok, body };
}

function loadBackendDeps() {
  const backendRequire = createRequire(path.join(repoRoot, 'backend/package.json'));
  const { initializeApp, cert, getApps } = backendRequire('firebase-admin/app');
  const { getAuth } = backendRequire('firebase-admin/auth');
  const { createClient } = backendRequire('@supabase/supabase-js');
  return { initializeApp, cert, getApps, getAuth, createClient };
}

async function mintFirebaseIdToken({ uid }) {
  const { initializeApp, cert, getApps, getAuth } = loadBackendDeps();

  if (getApps().length === 0) {
    const credentials = JSON.parse(readText('admin_dashboard/firebase-service-account.json'));
    initializeApp({
      credential: cert({
        projectId: credentials.project_id,
        clientEmail: credentials.client_email,
        privateKey: credentials.private_key,
      }),
      projectId: credentials.project_id,
    });
  }

  const customToken = await getAuth().createCustomToken(uid);
  const apiKey = readEnvFromFile('admin_dashboard/.env.local', 'NEXT_PUBLIC_FIREBASE_API_KEY');

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );

  const json = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`Firebase custom-token exchange failed: ${json?.error?.message || response.status}`);
  }

  const idToken = String(json?.idToken || '').trim();
  if (!idToken) {
    throw new Error('Firebase custom-token exchange returned no idToken');
  }

  return idToken;
}

function createSupabaseAdmin() {
  const { createClient } = loadBackendDeps();
  const projectRef = readText('supabase/.temp/project-ref').trim();
  const serviceRoleKey = readEnvFromFile('supabase/.env.local', 'SUPABASE_SERVICE_ROLE_KEY');
  return createClient(`https://${projectRef}.supabase.co`, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

function startProcess(command, args, env) {
  const child = spawn(command, args, {
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';

  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString();
    if (stdout.length > 8000) stdout = stdout.slice(-8000);
  });
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString();
    if (stderr.length > 8000) stderr = stderr.slice(-8000);
  });

  return { child, getLogs: () => ({ stdout, stderr }) };
}

async function main() {
  const summary = {
    baseUrl: null,
    startedLocalRedis: false,
    startedLocalBackend: false,
    personalFeed: null,
    personalFeedSync: null,
    tracked: null,
    userFeedUpdated: null,
    feedItemCounterDelta: null,
    cleanup: null,
  };

  const supabase = createSupabaseAdmin();

  // If BASE_URL is provided, use it. Otherwise start local Redis+backend.
  const externalBaseUrl = (process.env.BASE_URL || '').trim();
  const backendPort = Number.parseInt(process.env.PORT || '3111', 10);
  const redisPort = Number.parseInt(process.env.REDIS_PORT || '6382', 10);

  let redisProc = null;
  let backendProc = null;

  // Cleanup state
  let feedItemBefore = null;
  let engagementEventId = null;
  let testUid = null;

  try {
    let baseUrl;

    if (externalBaseUrl) {
      baseUrl = externalBaseUrl;
    } else {
      const redis = startProcess('redis-server', ['--port', String(redisPort), '--save', '', '--appendonly', 'no'], {});
      redisProc = redis;
      summary.startedLocalRedis = true;

      const serviceRoleKey = readEnvFromFile('supabase/.env.local', 'SUPABASE_SERVICE_ROLE_KEY');
      const projectRef = readText('supabase/.temp/project-ref').trim();

      const backendEnv = {
        PORT: String(backendPort),
        REDIS_URL: `redis://127.0.0.1:${redisPort}`,
        SUPABASE_URL: `https://${projectRef}.supabase.co`,
        SUPABASE_SERVICE_KEY: serviceRoleKey,
        GOOGLE_APPLICATION_CREDENTIALS: path.join(repoRoot, 'admin_dashboard/firebase-service-account.json'),
      };

      const backend = startProcess('node', [path.join(repoRoot, 'backend/dist/main.js')], backendEnv);
      backendProc = backend;
      summary.startedLocalBackend = true;
      baseUrl = `http://127.0.0.1:${backendPort}`;

      await waitForPort('127.0.0.1', backendPort, 20000);
    }

    summary.baseUrl = baseUrl;

    // Quick health probe via public endpoint.
    const globalProbe = await requestJson(`${baseUrl}/feed/global?limit=1`, {
      method: 'GET',
      headers: { accept: 'application/json' },
    });

    if (!globalProbe.ok || !Array.isArray(globalProbe.body)) {
      throw new Error(`GET /feed/global failed: ${globalProbe.status} ${JSON.stringify(globalProbe.body)}`);
    }

    testUid = `smoke-feed-${Date.now()}`;
    const idToken = await mintFirebaseIdToken({ uid: testUid });

    const personal = await requestJson(`${baseUrl}/feed/personal?limit=5`, {
      method: 'GET',
      headers: { authorization: `Bearer ${idToken}`, accept: 'application/json' },
    });

    if (!personal.ok || !Array.isArray(personal.body)) {
      throw new Error(`GET /feed/personal failed: ${personal.status} ${JSON.stringify(personal.body)}`);
    }

    summary.personalFeed = { count: personal.body.length };

    const feedItemsByKey = new Map();
    for (const item of personal.body) {
      const { data, error } = await supabase
        .from('feed_items')
        .select('id,item_type,item_id')
        .eq('item_type', item.type)
        .eq('item_id', item.itemId)
        .maybeSingle();

      if (error) {
        throw new Error(`Failed to verify persisted feed item ${item.type}:${item.itemId}: ${error.message}`);
      }

      if (data?.id) feedItemsByKey.set(`${item.type}:${item.itemId}`, data.id);
    }

    const { data: userFeedRows, error: userFeedError } = await supabase
      .from('user_feed')
      .select('feed_item_id')
      .eq('user_id', testUid);

    if (userFeedError) {
      throw new Error(`Failed to verify synced user_feed rows: ${userFeedError.message}`);
    }

    const syncedIds = new Set((userFeedRows || []).map((row) => row.feed_item_id));
    const syncedCount = [...feedItemsByKey.values()].filter((id) => syncedIds.has(id)).length;
    summary.personalFeedSync = {
      returnedCount: personal.body.length,
      persistedFeedItems: feedItemsByKey.size,
      syncedUserFeedRows: syncedCount,
    };

    const first = personal.body[0];
    if (!first?.type || !first?.itemId) {
      throw new Error('No trackable item returned by /feed/personal');
    }

    const { data: feedItemRow, error: feedItemRowError } = await supabase
      .from('feed_items')
      .select('id,view_count,score')
      .eq('item_type', first.type)
      .eq('item_id', first.itemId)
      .single();

    if (feedItemRowError) {
      throw new Error(`Failed to read feed_items before track: ${feedItemRowError.message}`);
    }

    feedItemBefore = { ...feedItemRow };

    const track = await requestJson(`${baseUrl}/feed/track`, {
      method: 'POST',
      headers: { authorization: `Bearer ${idToken}`, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        targetType: first.type,
        targetId: first.itemId,
        eventType: 'view',
        metadata: { source: 'tool/smoke_feed_track.mjs', createdAt: new Date().toISOString() },
      }),
    });

    if (!track.ok || track.body?.success !== true) {
      throw new Error(`POST /feed/track failed: ${track.status} ${JSON.stringify(track.body)}`);
    }

    summary.tracked = { ok: true };

    const { data: eventRows, error: eventError } = await supabase
      .from('engagement_events')
      .select('id,metadata,created_at')
      .eq('user_id', testUid)
      .eq('target_type', first.type)
      .eq('target_id', first.itemId)
      .eq('event_type', 'view')
      .order('created_at', { ascending: false })
      .limit(10);

    if (eventError) {
      throw new Error(`Failed to verify engagement_events after track: ${eventError.message}`);
    }

    const matching = (eventRows || []).find((row) => row.metadata?.source === 'tool/smoke_feed_track.mjs');
    if (!matching?.id) {
      throw new Error('No matching engagement event found after /feed/track');
    }

    engagementEventId = matching.id;

    const { data: userFeedAfter, error: userFeedAfterError } = await supabase
      .from('user_feed')
      .select('seen,engaged,engagement_type,seen_at')
      .eq('user_id', testUid)
      .eq('feed_item_id', feedItemBefore.id)
      .single();

    if (userFeedAfterError) {
      throw new Error(`Failed to verify user_feed after track: ${userFeedAfterError.message}`);
    }

    summary.userFeedUpdated = {
      seen: userFeedAfter.seen,
      engaged: userFeedAfter.engaged,
      engagement_type: userFeedAfter.engagement_type,
      has_seen_at: Boolean(userFeedAfter.seen_at),
    };

    const { data: feedItemAfter, error: feedItemAfterError } = await supabase
      .from('feed_items')
      .select('view_count,score')
      .eq('id', feedItemBefore.id)
      .single();

    if (feedItemAfterError) {
      throw new Error(`Failed to verify feed_items after track: ${feedItemAfterError.message}`);
    }

    summary.feedItemCounterDelta = {
      delta_view_count: Number(feedItemAfter.view_count) - Number(feedItemBefore.view_count),
      delta_score: Number(feedItemAfter.score) - Number(feedItemBefore.score),
    };

    summary.cleanup = { ok: true };
    console.log(JSON.stringify(summary, null, 2));
  } catch (error) {
    summary.cleanup = { ok: false, message: String(error?.message || error) };
    console.error(JSON.stringify(summary, null, 2));
    process.exitCode = 1;
  } finally {
    // Best-effort DB cleanup
    try {
      if (testUid) {
        await supabase.from('engagement_events').delete().eq('user_id', testUid);
        await supabase.from('user_feed').delete().eq('user_id', testUid);
      }
      if (feedItemBefore?.id) {
        await supabase
          .from('feed_items')
          .update({ view_count: feedItemBefore.view_count, score: feedItemBefore.score })
          .eq('id', feedItemBefore.id);
      }
    } catch (_) {
      // ignore cleanup failures
    }

    // Stop local services if we started them
    if (backendProc?.child && !backendProc.child.killed) {
      backendProc.child.kill('SIGTERM');
    }
    if (redisProc?.child && !redisProc.child.killed) {
      redisProc.child.kill('SIGTERM');
    }
  }
}

main();
