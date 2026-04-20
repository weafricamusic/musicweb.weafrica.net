# PostgreSQL Notify Pipeline (Backend + Push)

This project uses PostgreSQL LISTEN/NOTIFY for realtime fan-out to:
- Socket.IO (`weafrica:event`, `weafrica:live:update`, `weafrica:feed:update`)
- Optional FCM topic push notifications
- Optional push audit trail in `public.notification_event_audit`

## Components

- DB trigger migration:
  - `supabase/migrations/20260401113000_weafrica_event_notify_triggers.sql`
- Push audit migration:
  - `supabase/migrations/20260401124500_notification_event_audit.sql`
- Listener service:
  - `backend/src/services/postgresNotifyListener.js`
- Router service:
  - `backend/src/services/postgresNotifyRouter.js`
- Push service:
  - `backend/src/services/postgresNotifyPush.js`
- Audit writer:
  - `backend/src/services/postgresNotifyAudit.js`
- Runtime wiring:
  - `backend/src/server.js`
- SQL smoke test:
  - `supabase/sql/notify_smoke_test.sql`

## Required Environment Variables

### Listener
- `POSTGRES_LISTEN_URL` (preferred)
- Fallbacks used automatically: `DATABASE_URL`, `SUPABASE_DB_URL`
- `POSTGRES_LISTEN_CHANNEL` (optional, default: `weafrica_events`)

### Push (optional)
- `POSTGRES_NOTIFY_PUSH_ENABLED=true`
- Firebase credentials via one of:
  - `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`
  - `GOOGLE_APPLICATION_CREDENTIALS`
  - `firebase-service-account.json` in backend root

### Push tuning (optional)
- `POSTGRES_NOTIFY_PUSH_DEDUPE_MS`
- `POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_LIVE_SESSIONS`
- `POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_LIVE_BATTLES`
- `POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_SONGS_INSERT`
- `POSTGRES_NOTIFY_PUSH_COOLDOWN_MS_PHOTO_POSTS_INSERT`
- `POSTGRES_NOTIFY_PUSH_DISABLED_TOPICS` (CSV)
- `POSTGRES_NOTIFY_PUSH_ENABLED_TOPICS` (CSV allowlist)
- `POSTGRES_NOTIFY_PUSH_COUNTRY_ALLOWLIST` (CSV)
- `POSTGRES_NOTIFY_PUSH_COUNTRY_DENYLIST` (CSV)

## Event Payload Shape

Notifications sent on `weafrica_events` include:
- `event_id`
- `event_type`
- `table`
- `op`
- `entity_id`
- `actor_id`
- `country_code`
- `created_at`

## Client Action Mapping (Push)

The push service emits actions aligned with Flutter notification routing:
- `live_now`
- `live_battle_now`
- `track_detail`
- `content_refresh`

## Apply and Verify

1. Apply migrations in order.
2. Start backend with listener env configured.
3. Insert/update test rows (songs/live_sessions/live_battles/photo_song_posts).
4. Verify backend logs include `[pg-notify] routed ...`.
5. Verify Socket.IO clients receive events.
6. If push enabled, verify FCM topic notifications and audit rows.

### Runtime health endpoint

- `GET /health/notify`
- Returns listener status and counters, including:
  - `enabled`, `connected`, `channel`
  - `lastConnectedAt`, `lastEventAt`, `lastErrorAt`
  - connect/reconnect/error/notification counters

## Operational Notes

- LISTEN/NOTIFY requires a persistent backend process (not short-lived/serverless).
- Avoid triggering on `updated_at`-only changes to reduce event noise.
- Keep event payloads small and fetch rich details in app/backend if needed.
