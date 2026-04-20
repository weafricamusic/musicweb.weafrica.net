# Live production runbook (Supabase + Agora)

This repo supports a “Live” stack via Supabase (DB + Edge Function) and Agora (RTC).

## 1) Apply DB migrations to production

Link your CLI to the production Supabase project:

```bash
supabase link --project-ref <your-project-ref>
```

Push all migrations:

```bash
supabase db push --include-all
```

Minimum baseline for battles in this repo:

- `supabase/migrations/20260111113000_live_streams.sql`

Notes:

- The Edge Function `/api/battle/status` can read from `live_battles` (if you have that table) and falls back to `live_streams`.
- If your Live product requires additional tables (chat/likes, gifts, invites, payouts, etc.), ensure those migration files are present locally and included in the push.

## 2) Deploy the Edge Function

```bash
supabase functions deploy api --no-verify-jwt
```

Sanity check:

```bash
BASE_URL="https://<ref>.functions.supabase.co"
curl -sS "$BASE_URL/api/diag" \
  -H "x-debug-token: <WEAFRICA_DEBUG_DIAG_TOKEN>"
```

## 3) Set required Edge Function secrets

Edge Functions have their own environment (separate from Vercel).

Required:

- `AGORA_APP_ID`
- `AGORA_APP_CERTIFICATE`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREBASE_PROJECT_ID`
- `WEAFRICA_DEBUG_DIAG_TOKEN` (recommended: protects `/api/diag` in production)

CLI:

```bash
supabase secrets set \
  AGORA_APP_ID="..." \
  AGORA_APP_CERTIFICATE="..." \
  SUPABASE_SERVICE_ROLE_KEY="..." \
  FIREBASE_PROJECT_ID="weafrica-music-85cdc" \
  WEAFRICA_DEBUG_DIAG_TOKEN="..."

supabase functions deploy api --no-verify-jwt
```

## 4) Disable dev-only access in production

Production must have:

- `WEAFRICA_ENABLE_TEST_ROUTES` unset (or `false`)
- `WEAFRICA_TEST_TOKEN` removed

Confirm via `GET /api/diag`:

- `enable_test_routes=false`
- `has_test_token=false`

## 5) Run the Live smoke test

```bash
BASE_URL="https://<ref>.functions.supabase.co" bash tool/live/smoke_live.sh
```

To test authenticated flows (publisher token + battle ready), provide a Firebase ID token:

```bash
BASE_URL="https://<ref>.functions.supabase.co" \
  ID_TOKEN="$(FIREBASE_WEB_API_KEY="..." FIREBASE_EMAIL="you@example.com" FIREBASE_PASSWORD="your-password" node tool/ai_monetization/get-firebase-id-token.mjs)" \
  CHANNEL_ID="weafrica_battle_smoke" \
  BATTLE_ID="123" \
  bash tool/live/smoke_live.sh
```

### Troubleshooting: `/api/agora/token` returns 401 "Invalid Value"

That response usually means the client sent the wrong token type in `Authorization: Bearer ...`.

Fix:

- Make sure your mobile client uses a Firebase Auth **ID token** (e.g. `FirebaseAuth.instance.currentUser!.getIdToken()`), not an OAuth access token.
- Ensure the Edge Function secret `FIREBASE_PROJECT_ID` matches the Firebase project that minted the ID token.
- Recheck `GET /api/diag` for `has_firebase_project_id=true`.

## Product gap: Buy coins

The consumer Live UI still needs a real “Buy coins” flow (currently a placeholder snackbar). Until that’s implemented, users can spend coins (gifts) only if they already have a balance provisioned via purchases/subscriptions/admin adjustments.
