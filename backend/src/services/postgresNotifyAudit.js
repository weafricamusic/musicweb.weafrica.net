const { Pool } = require('pg');

let _pool = null;
let _disabled = false;

function resolveConnectionString() {
  return (
    process.env.POSTGRES_LISTEN_URL ||
    process.env.DATABASE_URL ||
    process.env.SUPABASE_DB_URL ||
    ''
  ).trim();
}

function getPool(logger = console) {
  if (_disabled) return null;
  if (_pool) return _pool;

  const connectionString = resolveConnectionString();
  if (!connectionString) {
    _disabled = true;
    logger.warn?.('[pg-notify-audit] disabled: missing DB connection string');
    return null;
  }

  _pool = new Pool({ connectionString, max: 4 });
  _pool.on('error', (error) => {
    logger.error?.('[pg-notify-audit] pool error', error);
  });
  return _pool;
}

async function writePushAudit(record, { logger = console } = {}) {
  try {
    const pool = getPool(logger);
    if (!pool) return;

    await pool.query(
      `insert into public.notification_event_audit (
        event_id,
        event_type,
        entity_id,
        actor_id,
        country_code,
        topic,
        status,
        reason,
        error
      ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [
        String(record.event_id || '').trim() || null,
        String(record.event_type || '').trim() || null,
        String(record.entity_id || '').trim() || null,
        String(record.actor_id || '').trim() || null,
        String(record.country_code || '').trim() || null,
        String(record.topic || '').trim() || null,
        String(record.status || '').trim() || null,
        String(record.reason || '').trim() || null,
        String(record.error || '').trim() || null,
      ],
    );
  } catch (error) {
    logger.error?.('[pg-notify-audit] write failed', error);
  }
}

module.exports = {
  writePushAudit,
};
