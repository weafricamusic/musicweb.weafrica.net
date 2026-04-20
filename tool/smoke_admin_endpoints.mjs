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

async function mintFirebaseIdToken(uid) {
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
  if (!response.ok || !json?.idToken) {
    throw new Error(`Firebase custom-token exchange failed: ${json?.error?.message || response.status}`);
  }

  return String(json.idToken);
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

function summarizeBody(body) {
  if (Array.isArray(body)) {
    return { type: 'array', count: body.length, firstKeys: body[0] ? Object.keys(body[0]).slice(0, 8) : [] };
  }

  if (body && typeof body === 'object') {
    return { type: 'object', keys: Object.keys(body).slice(0, 12) };
  }

  return body;
}

async function main() {
  const summary = {
    baseUrl: null,
    startedLocalRedis: false,
    startedLocalBackend: false,
    tempAdminUid: null,
    endpoints: {},
    mutations: {},
    cleanupOk: false,
    cleanupError: null,
  };

  const supabase = createSupabaseAdmin();
  const externalBaseUrl = (process.env.BASE_URL || '').trim();
  const backendPort = Number.parseInt(process.env.PORT || '3120', 10);
  const redisPort = Number.parseInt(process.env.REDIS_PORT || '6383', 10);

  let redisProc = null;
  let backendProc = null;
  let tempAdminUid = null;
  const cleanupTasks = [];

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

    tempAdminUid = `admin-smoke-${Date.now()}`;
    summary.tempAdminUid = tempAdminUid;
    const token = await mintFirebaseIdToken(tempAdminUid);
    const now = new Date().toISOString();

    const { error: profileError } = await supabase.from('profiles').upsert({
      id: tempAdminUid,
      email: `${tempAdminUid}@example.test`,
      display_name: 'Admin Smoke Test',
      is_admin: true,
      admin_role: 'super_admin',
      status: 'active',
      created_at: now,
      updated_at: now,
    });

    if (profileError) {
      throw new Error(`Failed to prepare temp admin profile: ${profileError.message}`);
    }

    cleanupTasks.push(async () => {
      await supabase.from('profiles').delete().eq('id', tempAdminUid);
    });

    const targets = [
      ['dashboard', `${baseUrl}/admin/dashboard`],
      ['realtime', `${baseUrl}/admin/metrics/realtime`],
      ['viral', `${baseUrl}/admin/viral`],
      ['reports', `${baseUrl}/admin/reports?status=pending&limit=5`],
      ['streams', `${baseUrl}/admin/streams?status=live&limit=5`],
      ['users', `${baseUrl}/admin/users?limit=2`],
      ['health', `${baseUrl}/admin/health`],
    ];

    for (const [label, url] of targets) {
      const result = await requestJson(url, {
        method: 'GET',
        headers: {
          authorization: `Bearer ${token}`,
          accept: 'application/json',
        },
      });

      summary.endpoints[label] = {
        status: result.status,
        ok: result.ok,
        summary: summarizeBody(result.body),
        error: result.ok ? null : result.body,
      };
    }

    const reportTargetId = `smoke-report-${Date.now()}`;
    const { data: reportRow, error: reportInsertError } = await supabase
      .from('content_reports')
      .insert({
        reporter_id: tempAdminUid,
        target_type: 'song',
        target_id: reportTargetId,
        reason: 'other',
        description: 'Smoke moderation review',
        status: 'pending',
        details: {},
        created_at: now,
      })
      .select('id')
      .single();

    if (reportInsertError) {
      throw new Error(`Failed to create smoke report: ${reportInsertError.message}`);
    }

    cleanupTasks.push(async () => {
      await supabase.from('content_reports').delete().eq('id', reportRow.id);
    });

    const reportReview = await requestJson(`${baseUrl}/admin/reports/${reportRow.id}/review`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ action: 'dismiss', notes: 'smoke test' }),
    });

    summary.mutations.report_review = {
      status: reportReview.status,
      ok: reportReview.ok,
      summary: summarizeBody(reportReview.body),
      error: reportReview.ok ? null : reportReview.body,
    };

    const flagTargetId = `smoke-flag-${Date.now()}`;
    const { data: flagRow, error: flagInsertError } = await supabase
      .from('content_flags')
      .insert({
        content_type: 'song',
        content_id: flagTargetId,
        reported_by: tempAdminUid,
        reason: 'other',
        severity: 1,
        status: 'pending',
        created_at: now,
      })
      .select('id')
      .single();

    if (flagInsertError) {
      throw new Error(`Failed to create smoke content flag: ${flagInsertError.message}`);
    }

    cleanupTasks.push(async () => {
      await supabase.from('content_flags').delete().eq('id', flagRow.id);
    });

    const flagResolution = await requestJson(`${baseUrl}/admin/content/flags/${flagRow.id}/resolve`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ action: 'dismiss', notes: 'smoke test' }),
    });

    summary.mutations.flag_resolution = {
      status: flagResolution.status,
      ok: flagResolution.ok,
      summary: summarizeBody(flagResolution.body),
      error: flagResolution.ok ? null : flagResolution.body,
    };

    let financeSource = 'withdrawals';
    let financeId = null;
    try {
      const { data: withdrawalRow, error: withdrawalInsertError } = await supabase
        .from('withdrawals')
        .insert({
          beneficiary_type: 'artist',
          beneficiary_id: tempAdminUid,
          amount_mwk: 1234,
          method: 'bank_transfer',
          status: 'pending',
          requested_at: now,
          admin_email: null,
          note: 'smoke test',
          meta: {},
        })
        .select('id')
        .single();
      if (withdrawalInsertError) throw withdrawalInsertError;
      financeId = String(withdrawalRow.id);
      cleanupTasks.push(async () => {
        await supabase.from('withdrawals').delete().eq('id', withdrawalRow.id);
      });
    } catch {
      financeSource = 'withdrawal_requests';
      const { data: withdrawalRequestRow, error: withdrawalRequestInsertError } = await supabase
        .from('withdrawal_requests')
        .insert({
          user_id: tempAdminUid,
          amount: 1234,
          status: 'pending',
          payment_method: 'bank_transfer',
          account_details: {},
          admin_notes: 'smoke test',
          created_at: now,
          updated_at: now,
        })
        .select('id')
        .single();
      if (withdrawalRequestInsertError) {
        throw new Error(`Failed to create smoke withdrawal: ${withdrawalRequestInsertError.message}`);
      }
      financeId = String(withdrawalRequestRow.id);
      cleanupTasks.push(async () => {
        await supabase.from('withdrawal_requests').delete().eq('id', withdrawalRequestRow.id);
      });
    }

    const financeApprove = await requestJson(`${baseUrl}/admin/finance/withdrawals/${financeId}/process`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ action: 'approve', notes: 'smoke test', source: financeSource }),
    });

    const financeMarkPaid = await requestJson(`${baseUrl}/admin/finance/withdrawals/${financeId}/process`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ action: 'mark_paid', notes: 'smoke test', source: financeSource }),
    });

    summary.mutations.finance_processing = {
      approve: {
        status: financeApprove.status,
        ok: financeApprove.ok,
        summary: summarizeBody(financeApprove.body),
        error: financeApprove.ok ? null : financeApprove.body,
      },
      mark_paid: {
        status: financeMarkPaid.status,
        ok: financeMarkPaid.ok,
        summary: summarizeBody(financeMarkPaid.body),
        error: financeMarkPaid.ok ? null : financeMarkPaid.body,
      },
    };

    const liveChannelId = `smoke_live_${Date.now()}`;
    const { data: liveSessionRow, error: liveSessionInsertError } = await supabase
      .from('live_sessions')
      .insert({
        channel_id: liveChannelId,
        host_id: tempAdminUid,
        host_name: 'Smoke Host',
        title: 'Smoke Live Session',
        is_live: true,
        started_at: now,
        created_at: now,
        updated_at: now,
        host_type: 'artist',
        stream_type: 'artist_live',
        region: 'MW',
      })
      .select('id')
      .single();

    if (liveSessionInsertError) {
      throw new Error(`Failed to create smoke live session: ${liveSessionInsertError.message}`);
    }

    cleanupTasks.push(async () => {
      await supabase.from('live_sessions').delete().eq('id', liveSessionRow.id);
    });

    const streamStop = await requestJson(`${baseUrl}/admin/streams/${liveSessionRow.id}/stop`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ reason: 'smoke test' }),
    });

    summary.mutations.stream_stop = {
      status: streamStop.status,
      ok: streamStop.ok,
      summary: summarizeBody(streamStop.body),
      error: streamStop.ok ? null : streamStop.body,
    };
  } finally {
    let cleanupError = null;
    while (cleanupTasks.length) {
      const task = cleanupTasks.pop();
      try {
        await task();
      } catch (error) {
        cleanupError = error instanceof Error ? error.message : String(error);
      }
    }

    summary.cleanupOk = cleanupError == null;
    summary.cleanupError = cleanupError;

    if (backendProc?.child) {
      backendProc.child.kill('SIGTERM');
    }

    if (redisProc?.child) {
      redisProc.child.kill('SIGTERM');
    }
  }

  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
