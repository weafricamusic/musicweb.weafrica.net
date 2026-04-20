const { sendPushForEvent } = require('./postgresNotifyPush');

async function routePostgresEvent(event, { io, logger = console } = {}) {
  if (!event || typeof event !== 'object') return;

  try {
    if (io && typeof io.emit === 'function') {
      io.emit('weafrica:event', event);

      const eventType = String(event.event_type || '').trim();
      if (eventType.startsWith('live_battles.') || eventType.startsWith('live_sessions.')) {
        io.emit('weafrica:live:update', event);
      }

      if (eventType.startsWith('photo_song_posts.') || eventType.startsWith('songs.')) {
        io.emit('weafrica:feed:update', event);
      }
    }

    logger.log?.(
      `[pg-notify] routed ${event.event_type || 'unknown'} entity=${event.entity_id || 'n/a'}`,
    );

    await sendPushForEvent(event, { logger });
  } catch (error) {
    logger.error?.('[pg-notify] route failed', error);
  }
}

module.exports = {
  routePostgresEvent,
};
