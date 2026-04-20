const winston = require('winston');

// Define log format
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.json()
);

// Create logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: logFormat,
  defaultMeta: { service: 'weafrica-api' },
  transports: [
    // Write all logs with importance level of `error` or less to `error.log`
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    // Write all logs with importance level of `info` or less to `combined.log`
    new winston.transports.File({ filename: 'logs/combined.log' }),
  ],
});

// If we're not in production then log to the console with a simple format
if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.simple()
    )
  }));
}

// Battle-specific logging
const logBattleEvent = (battleId, event, data = {}) => {
  logger.info('Battle Event', {
    battleId,
    event,
    ...data,
    timestamp: new Date().toISOString()
  });
};

// Gift logging
const logGift = (giftData) => {
  logger.info('Gift Sent', {
    ...giftData,
    timestamp: new Date().toISOString()
  });
};

// Error logging
const logError = (error, context = {}) => {
  logger.error('Application Error', {
    error: error.message,
    stack: error.stack,
    context,
    timestamp: new Date().toISOString()
  });
};

// Request logging middleware
const requestLogger = (req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info('HTTP Request', {
      method: req.method,
      url: req.url,
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      userAgent: req.get('User-Agent')
    });
  });

  next();
};

module.exports = {
  logger,
  logBattleEvent,
  logGift,
  logError,
  requestLogger
};