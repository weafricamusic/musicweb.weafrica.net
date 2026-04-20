# Step 13 — AI Monetization Engine (Deploy Notes)

You hit this error:

> ERROR: 42601: syntax error at or near "//" LINE 1: // Supabase Edge Function: api

That happens when TypeScript (Edge Function code) is pasted into the **SQL editor**.

## What goes where

- **SQL (migrations / tables / functions):**
  - File: `supabase/migrations/20260207010000_ai_monetization_engine.sql`
  - Additional hardening: `supabase/migrations/20260208123000_ai_credit_ledger.sql`
  - Run via:
    - CLI: `supabase db push --include-all`
    - or Supabase Dashboard → **SQL Editor**: paste the contents of the `.sql` migration.

- **Edge Function (TypeScript API routes):**
  - File: `supabase/functions/api/index.ts`
  - Deploy via CLI:
    - `supabase functions deploy api --no-verify-jwt`
  - Do **not** paste this file into SQL Editor.

## Minimal deployment sequence

1) Apply DB migration (Step 13 tables + RPCs)

- `supabase db push --include-all`

2) Deploy the Edge Function

- `supabase functions deploy api --no-verify-jwt`

3) (Optional) Configure env vars on the Edge Function

- `WEAFRICA_AI_REWARD_WIN_CREDITS` (default: 20)
- `WEAFRICA_AI_CROWD_BOOST_COINS_PER_MIN` (default: 15)

## Production checklist ("no demo")

- Ensure `WEAFRICA_ENABLE_TEST_ROUTES` is NOT set to `true` in production.
  - If it’s `true`, anyone with the test token can hit test-only fallbacks.
- Confirm production auth behavior:
  - `POST /api/beat/generate` should require a valid Firebase `Authorization: Bearer <ID_TOKEN>`.
  - Test-token access is dev-only and only works when `WEAFRICA_ENABLE_TEST_ROUTES=true`.
- Confirm the DB objects exist (from the migration):
  - Tables: `ai_pricing`, `ai_usage_daily`, `ai_credit_wallets`, `ai_credit_ledger`, `ai_spend_events`
  - RPCs: `ai_record_usage`, `ai_spend_credits`, `ai_grant_credits_once`, `ai_spend_coins`
- Verify monetization is enforced:
  - Call `POST /api/beat/generate` 4 times in one UTC day as a free user → 4th should return `402 payment_required`.
- Verify real balances are used:
  - `GET /api/ai/balance` should reflect `wallets.coin_balance` and `ai_credit_wallets.credit_balance`.

## Quick smoke checks (after deploy)

- `GET /api/ai/pricing`
- `GET /api/ai/balance` (requires Firebase Bearer token)
- `POST /api/beat/generate` (now enforces free limit + spend)

## Beat MP3 generation (production)

This is the "press a button → get an MP3" flow.

- DB: apply migration [supabase/migrations/20260208060000_ai_beat_audio_jobs.sql](supabase/migrations/20260208060000_ai_beat_audio_jobs.sql)
- Edge env vars:
  - `REPLICATE_API_TOKEN` (required)
  - `WEAFRICA_REPLICATE_MUSIC_MODEL` (default: `meta/musicgen`)
  - `WEAFRICA_REPLICATE_MUSIC_VERSION` (optional; if set, uses `/v1/predictions` with version)
  - `WEAFRICA_AI_BEATS_BUCKET` (default: `ai_beats`)

Endpoints:
- `POST /api/beat/audio/start` (auth; charges `beat_audio_generation`) → `{ job_id, status, prompt }`
- `GET /api/beat/audio/status?job_id=...` (auth) → `{ job: { status, audio_url? } }`

### Getting a Firebase ID token (for smoke tests)

Avoid pasting tokens into chat/logs. Run the smoke test locally.

- From a logged-in Flutter app session (quick debug snippet):
  - `final t = await FirebaseAuth.instance.currentUser?.getIdToken(true);`
  - Print `t` in debug console temporarily.

- From email/password (local script; prints token to stdout only):
  - Script: `tool/ai_monetization/get-firebase-id-token.mjs` (or repo root `get-firebase-id-token.mjs`)
  - Run without printing token:
    - `ID_TOKEN="$(FIREBASE_WEB_API_KEY=... FIREBASE_EMAIL=... FIREBASE_PASSWORD=... node tool/ai_monetization/get-firebase-id-token.mjs)" \
BASE_URL="https://<ref>.functions.supabase.co" \
bash tool/ai_monetization/smoke_test.sh`

API key env var: prefers `FIREBASE_WEB_API_KEY`, falls back to `NEXT_PUBLIC_FIREBASE_API_KEY`.

- Run the script:
  - `BASE_URL="https://<ref>.functions.supabase.co" ID_TOKEN="<token>" ./tool/ai_monetization/smoke_test.sh`

If `ID_TOKEN` is not set (and you didn’t set a dev-only `TEST_TOKEN`), the script will skip the authenticated checks.
