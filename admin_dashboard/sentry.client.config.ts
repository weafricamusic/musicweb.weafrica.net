import * as Sentry from '@sentry/nextjs'

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN || undefined,
  tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? '0.05'),
  replaysOnErrorSampleRate: Number(process.env.SENTRY_REPLAYS_ON_ERROR_SAMPLE_RATE ?? '1.0'),
  replaysSessionSampleRate: Number(process.env.SENTRY_REPLAYS_SESSION_SAMPLE_RATE ?? '0.1'),
  enabled: !!(process.env.NEXT_PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN),
})
