const { Client } = require('pg');
const { routePostgresEvent } = require('./postgresNotifyRouter');

function resolveConnectionString() {
  return (
    process.env.POSTGRES_LISTEN_URL ||
    process.env.DATABASE_URL ||
    process.env.SUPABASE_DB_URL ||
    ''
  ).trim();
}

function startPostgresNotifyListener({ io, logger = console } = {}) {
  const connectionString = resolveConnectionString();
  const channel = (process.env.POSTGRES_LISTEN_CHANNEL || 'weafrica_events').trim();
  const state = {
    enabled: Boolean(connectionString),
    channel,
    connected: false,
    reconnectScheduled: false,
    startedAt: new Date().toISOString(),
    lastConnectedAt: null,
    lastEventAt: null,
    lastErrorAt: null,
    counters: {
      connectAttempts: 0,
      connectFailures: 0,
      reconnects: 0,
      notifications: 0,
      invalidPayloads: 0,
      errors: 0,
    },
  };

  const getStatus = () => ({
    enabled: state.enabled,
    channel: state.channel,
    connected: state.connected,
    reconnectScheduled: state.reconnectScheduled,
    startedAt: state.startedAt,
    lastConnectedAt: state.lastConnectedAt,
    lastEventAt: state.lastEventAt,
    lastErrorAt: state.lastErrorAt,
    counters: { ...state.counters },
  });

  if (!connectionString) {
    logger.warn?.(
      '[pg-notify] listener disabled: set POSTGRES_LISTEN_URL (or DATABASE_URL/SUPABASE_DB_URL)',
    );
    return {
      stop: async () => {},
      getStatus,
    };
  }

  let client = null;
  let stopped = false;
  let reconnectTimer = null;

  const scheduleReconnect = () => {
    if (stopped || reconnectTimer) return;
    state.reconnectScheduled = true;
    state.counters.reconnects += 1;
    reconnectTimer = setTimeout(async () => {
      reconnectTimer = null;
      state.reconnectScheduled = false;
      await connectAndListen();
    }, 3000);
  };

  const connectAndListen = async () => {
    if (stopped) return;
    state.counters.connectAttempts += 1;

    client = new Client({ connectionString });

    try {
      await client.connect();
      await client.query(`LISTEN ${channel}`);
      state.connected = true;
      state.lastConnectedAt = new Date().toISOString();
      logger.log?.(`[pg-notify] listening on channel "${channel}"`);
    } catch (error) {
      state.counters.connectFailures += 1;
      state.counters.errors += 1;
      state.lastErrorAt = new Date().toISOString();
      logger.error?.('[pg-notify] connect/listen failed', error);
      scheduleReconnect();
      return;
    }

    client.on('notification', (msg) => {
      if (!msg || !msg.payload) return;
      state.counters.notifications += 1;
      state.lastEventAt = new Date().toISOString();

      let payload;
      try {
        payload = JSON.parse(msg.payload);
      } catch (error) {
        state.counters.invalidPayloads += 1;
        state.counters.errors += 1;
        state.lastErrorAt = new Date().toISOString();
        logger.error?.('[pg-notify] invalid JSON payload', error);
        return;
      }

      void routePostgresEvent(payload, { io, logger });
    });

    client.on('error', (error) => {
      state.connected = false;
      state.counters.errors += 1;
      state.lastErrorAt = new Date().toISOString();
      logger.error?.('[pg-notify] client error', error);
      scheduleReconnect();
    });

    client.on('end', () => {
      if (stopped) return;
      state.connected = false;
      logger.warn?.('[pg-notify] connection ended; reconnecting...');
      scheduleReconnect();
    });
  };

  connectAndListen();

  return {
    stop: async () => {
      stopped = true;
      state.connected = false;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
        state.reconnectScheduled = false;
      }
      try {
        await client?.end();
      } catch (_) {}
    },
    getStatus,
  };
}

module.exports = {
  startPostgresNotifyListener,
};
