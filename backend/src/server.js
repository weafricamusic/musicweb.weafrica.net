const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { startJourneyDispatchCron } = require('./cron/journey_dispatch_cron');
const { startPostgresNotifyListener } = require('./services/postgresNotifyListener');
require('dotenv').config();

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: ['https://weafrica.com', 'https://musicweb.weafrica.net', 'capacitor://localhost'],
    credentials: true
  }
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api', limiter);

// Routes
app.use('/api/auth', require('./api/auth'));
app.use('/api/battles', require('./api/battles'));
app.use('/api/gifts', require('./api/gifts'));
app.use('/api/users', require('./api/users'));
app.use('/api/payments', require('./api/payments'));
app.use('/api/analytics', require('./api/analytics'));
app.use('/api/songs', require('./api/songs'));

// WebSocket for real-time battle updates
io.on('connection', (socket) => {
  console.log('New client connected:', socket.id);

  socket.on('join-battle', (battleId) => {
    socket.join(`battle:${battleId}`);
  });

  socket.on('leave-battle', (battleId) => {
    socket.leave(`battle:${battleId}`);
  });

  socket.on('send-gift', (data) => {
    io.to(`battle:${data.battleId}`).emit('new-gift', data);
  });

  socket.on('send-message', (data) => {
    io.to(`battle:${data.battleId}`).emit('new-message', data);
  });

  socket.on('battle-update', (data) => {
    io.to(`battle:${data.battleId}`).emit('battle-state', data);
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/health/notify', (req, res) => {
  const notify =
    typeof pgNotifyListener?.getStatus === 'function'
      ? pgNotifyListener.getStatus()
      : { enabled: false };

  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    notify,
  });
});

// Start server
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});

const pgNotifyListener = startPostgresNotifyListener({ io, logger: console });

const shutdown = async () => {
  try {
    await pgNotifyListener.stop();
  } catch (_) { }
  process.exit(0);
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// Optional: scheduled dispatch of due journey pushes.
startJourneyDispatchCron();

module.exports = { app, io };