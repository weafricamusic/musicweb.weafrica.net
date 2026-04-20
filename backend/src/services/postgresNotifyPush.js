const { existsSync, readFileSync } = require('fs');
const { join } = require('path');
const { getApps, initializeApp, cert, applicationDefault } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const { writePushAudit } = require('./postgresNotifyAudit');

const _recentPushKeys = new Map();

function isEnabled() {
  const flag = String(process.env.POSTGRES_NOTIFY_PUSH_ENABLED || '').trim().toLowerCase();
  return flag === '1' || flag === 'true' || flag === 'yes';
}

function readInlineCredential() {
  const projectId = String(process.env.FIREBASE_PROJECT_ID || '').trim();
  const clientEmail = String(process.env.FIREBASE_CLIENT_EMAIL || '').trim();
  const privateKey = String(process.env.FIREBASE_PRIVATE_KEY || '').trim().replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey) return null;
  return { projectId, clientEmail, privateKey };
}

function readFileCredential() {
  const explicitPath = String(process.env.GOOGLE_APPLICATION_CREDENTIALS || '').trim();
  const candidates = [
    explicitPath,
    join(process.cwd(), 'firebase-service-account.json'),
    join(process.cwd(), '..', 'admin_dashboard', 'firebase-service-account.json'),
  ].filter(Boolean);

  for (const path of candidates) {
    if (!existsSync(path)) continue;
    try {
      const raw = JSON.parse(readFileSync(path, 'utf8'));
      const projectId = String(raw.project_id || '').trim();
      const clientEmail = String(raw.client_email || '').trim();
      const privateKey = String(raw.private_key || '').trim();
      if (projectId && clientEmail && privateKey) {
        return { projectId, clientEmail, privateKey };
      }
    } catch (_) {}
  }
  return null;
}

function getFirebaseApp(logger = console) {
  const existing = getApps();
  if (existing.length > 0) return existing[0];

  const inline = readInlineCredential();
  if (inline) {
    return initializeApp({
      credential: cert({
        projectId: inline.projectId,
        clientEmail: inline.clientEmail,
        privateKey: inline.privateKey,
      }),
      projectId: inline.projectId,
    });
  }

  const file = readFileCredential();
  if (file) {
    return initializeApp({
      credential: cert({
        projectId: file.projectId,
        clientEmail: file.clientEmail,
        privateKey: file.privateKey,
      }),
      projectId: file.projectId,
    });
  }

  logger.warn?.('[pg-notify-push] Firebase credentials not found; falling back to applicationDefault().');
  return initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
}

function pushSpecForEvent(event) {
  const type = String(event?.event_type || '').trim();
  if (!type) return null;

  if (type.startsWith('live_sessions.')) {
    return {
      topics: ['consumers', 'artists', 'djs'],
      title: 'Live Now',
      body: 'A new live session is available.',
      action: 'live_now',
      target_tab: 'live',
    };
  }

  if (type.startsWith('live_battles.')) {
    return {
      topics: ['consumers', 'artists', 'djs'],
      title: 'Battle Update',
      body: 'A live battle has been updated.',
      action: 'live_battle_now',
      target_tab: 'live',
    };
  }

  if (type === 'songs.insert') {
    return {
      topics: ['consumers'],
      title: 'New Song Added',
      body: 'Fresh music is now available in your feed.',
      action: 'track_detail',
      target_tab: 'home',
    };
  }

  if (type === 'photo_song_posts.insert') {
    return {
      topics: ['consumers'],
      title: 'New Photo + Song Post',
      body: 'A creator posted a new photo with music.',
      action: 'content_refresh',
      target_tab: 'home',
    };
  }

  return null;
}

function dedupeWindowMs() {
  const raw = Number.parseInt(String(process.env.POSTGRES_NOTIFY_PUSH_DEDUPE_MS || ''), 10);
  if (Number.isFinite(raw) && raw >= 1000) return raw;
  return 30000;
}

function cooldownMsForType(eventType) {
  const type = String(eventType || '').trim();
  const fallback = dedupeWindowMs();

  const envValue = (name) => {
    const raw = Number.parseInt(String(process.env[name] || ''), 10);
    return Number.isFinite(raw) && raw >= 1000 ? raw : null;
  };

  if (type.startsWith('live_sessions.')) {
    return envValue('POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_LIVE_SESSIONS') ?? 12000;
  }

  if (type.startsWith('live_battles.')) {
    return envValue('POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_LIVE_BATTLES') ?? 15000;
  }

  if (type === 'songs.insert') {
    return envValue('POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_SONGS_INSERT') ?? 90000;
  }

  if (type === 'photo_song_posts.insert') {
    return envValue('POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_PHOTO_POSTS_INSERT') ?? 45000;
  }

  return fallback;
}

function makePushKey(event) {
  const eventId = String(event?.event_id || '').trim();
  if (eventId) return eventId;
  const type = String(event?.event_type || '').trim();
  const entity = String(event?.entity_id || '').trim();
  const actor = String(event?.actor_id || '').trim();
  return `${type}|${entity}|${actor}`;
}

function shouldSkipByDedupe(event) {
  const now = Date.now();
  const key = makePushKey(event);
  if (!key) return false;

  const windowMs = cooldownMsForType(event?.event_type);
  const seenAt = _recentPushKeys.get(key);
  if (typeof seenAt === 'number' && now - seenAt < windowMs) {
    return true;
  }

  _recentPushKeys.set(key, now);

  for (const [k, ts] of _recentPushKeys.entries()) {
    if (now - ts > windowMs * 3) {
      _recentPushKeys.delete(k);
    }
  }

  return false;
}

function parseCsvEnv(name) {
  return new Set(
    String(process.env[name] || '')
      .split(',')
      .map((v) => v.trim().toLowerCase())
      .filter(Boolean),
  );
}

function filterTopics(topics, event) {
  const out = Array.from(
    new Set((topics || []).map((v) => String(v || '').trim()).filter(Boolean)),
  );

  if (!out.length) return out;

  const disabled = parseCsvEnv('POSTGRES_NOTIFY_PUSH_DISABLED_TOPICS');
  const enabled = parseCsvEnv('POSTGRES_NOTIFY_PUSH_ENABLED_TOPICS');

  let filtered = out.filter((topic) => !disabled.has(topic.toLowerCase()));
  if (enabled.size) {
    filtered = filtered.filter((topic) => enabled.has(topic.toLowerCase()));
  }

  const country = String(event?.country_code || '').trim().toLowerCase();
  const countryAllow = parseCsvEnv('POSTGRES_NOTIFY_PUSH_COUNTRY_ALLOWLIST');
  const countryDeny = parseCsvEnv('POSTGRES_NOTIFY_PUSH_COUNTRY_DENYLIST');
  if (country && countryDeny.has(country)) {
    return [];
  }
  if (countryAllow.size && country && !countryAllow.has(country)) {
    return [];
  }

  return filtered;
}

async function sendPushForEvent(event, { logger = console } = {}) {
  if (!isEnabled()) return;
  if (shouldSkipByDedupe(event)) {
    logger.log?.(`[pg-notify-push] skipped duplicate type=${event?.event_type || 'unknown'}`);
    await writePushAudit(
      {
        ...event,
        status: 'skipped',
        reason: 'dedupe',
      },
      { logger },
    );
    return;
  }

  const spec = pushSpecForEvent(event);
  if (!spec) {
    await writePushAudit(
      {
        ...event,
        status: 'skipped',
        reason: 'no_push_spec',
      },
      { logger },
    );
    return;
  }

  try {
    const app = getFirebaseApp(logger);
    const messaging = getMessaging(app);

    const data = {
      event_type: String(event.event_type || ''),
      entity_id: String(event.entity_id || ''),
      actor_id: String(event.actor_id || ''),
      created_at: String(event.created_at || ''),
      action: String(spec.action || ''),
      target_tab: String(spec.target_tab || ''),
    };

    const topics = filterTopics(spec.topics, event);
    if (!topics.length) {
      await writePushAudit(
        {
          ...event,
          status: 'skipped',
          reason: 'topic_filtered',
        },
        { logger },
      );
      return;
    }

    for (const topic of topics) {
      await messaging.send({
        topic,
        notification: {
          title: spec.title,
          body: spec.body,
        },
        data,
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-priority': '10' },
        },
      });

      logger.log?.(`[pg-notify-push] sent topic=${topic} type=${event.event_type}`);
      await writePushAudit(
        {
          ...event,
          topic,
          status: 'sent',
        },
        { logger },
      );
    }
  } catch (error) {
    logger.error?.('[pg-notify-push] send failed', error);
    await writePushAudit(
      {
        ...event,
        status: 'failed',
        reason: 'send_error',
        error: error instanceof Error ? error.message : String(error),
      },
      { logger },
    );
  }
}

module.exports = {
  sendPushForEvent,
};
