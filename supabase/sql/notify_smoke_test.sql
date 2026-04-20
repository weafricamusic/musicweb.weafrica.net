-- PostgreSQL NOTIFY smoke test for WeAfrica event pipeline.
-- Run in a SQL client connected to the same DB as backend listener.

-- 1) In session A, subscribe to channels:
-- LISTEN weafrica_events;
-- LISTEN pgrst;

-- 2) In session B, run one of these test emits:
select pg_notify(
  'weafrica_events',
  json_build_object(
    'event_id', gen_random_uuid()::text,
    'event_type', 'photo_song_posts.insert',
    'table', 'photo_song_posts',
    'op', 'insert',
    'entity_id', 'smoke-test-post-1',
    'actor_id', 'smoke-test-user',
    'country_code', 'mw',
    'created_at', now()
  )::text
);

select pg_notify(
  'weafrica_events',
  json_build_object(
    'event_id', gen_random_uuid()::text,
    'event_type', 'live_sessions.insert',
    'table', 'live_sessions',
    'op', 'insert',
    'entity_id', 'smoke-test-live-1',
    'actor_id', 'smoke-test-host',
    'country_code', 'mw',
    'created_at', now()
  )::text
);

-- 3) Optional pgrst schema reload signal check:
select pg_notify('pgrst', 'reload schema');

-- Expected:
-- - Session A receives async notifications.
-- - Backend logs include [pg-notify] routed ...
-- - If push is enabled, backend logs include [pg-notify-push] sent ...
-- - /health/notify reflects notification counters and lastEventAt.
