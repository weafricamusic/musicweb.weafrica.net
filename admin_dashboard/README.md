This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

This copy is used inside `weafrica_music` as an admin-only dashboard deployment. Separate artist and DJ routes redirect to the admin login, and creator-only API namespaces are blocked.

## Getting Started

This repo targets Node.js 20.x (see `package.json` → `engines`). If you use `nvm`:

```bash
nvm use
```

## Environment Variables

Copy the template and fill in your values:

```bash
cp .env.example .env.local
```

Or use the repo helper (recommended):

```bash
npm run setup:env
```

Supabase (admin pages / subscriptions):

```bash
# Fills NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY from existing local Flutter config when available
npm run setup:supabase

# Set the server-only service role key (macOS): copy the key from Supabase Dashboard → Project Settings → API
npm run setup:supabase -- --service-from-clipboard
```

If your consumer app loads configuration from an asset JSON file, this repo also includes a template:

```bash
cp supabase.env.json.example supabase.env.json
```

Backend access control lives in:

- `firestore.rules` (Firebase Auth + Firestore)
- `supabase/migrations/` (Supabase RLS policies for songs/videos)

Required for the login page (Firebase Web App config):

- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`

Required for creating the admin session cookie after login (Firebase Admin SDK service account):

- Set exactly one of: `FIREBASE_SERVICE_ACCOUNT_PATH` (or `GOOGLE_APPLICATION_CREDENTIALS`), `FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_SERVICE_ACCOUNT_BASE64`

Local dev helper (creates `firebase-service-account.json` in this folder; gitignored):

```bash
# macOS: copy the downloaded service account JSON to clipboard first
npm run setup:firebase-admin -- --from-clipboard

# or copy from an existing downloaded key file
npm run setup:firebase-admin -- --from ~/Downloads/<your-service-account>.json
```

After editing `.env.local`, restart the dev server so Next.js picks up env changes.

Required to fetch data from the NestJS admin API (users, moderation, finance, etc):

- `ADMIN_BACKEND_BASE_URL` (server-only). Example: `http://127.0.0.1:3000` (local) or `https://api.yourdomain.com` (production).

## Test accounts (dev/staging)

To ensure the default test emails have an active **Platinum** subscription and the required Supabase rows:

```bash
# dry-run (no writes)
npm run ensure:test-accounts -- --dry-run

# apply writes (creates missing Firebase users, seeds subscriptions, activates artist/dj rows, upserts admin row)
TEST_ACCOUNT_PASSWORD="ChangeMe123!" npm run ensure:test-accounts -- --apply
```

Notes:

- Admin login is still protected by `ADMIN_EMAILS` + `ADMIN_GUARD_SECRET`. Make sure `ADMIN_EMAILS` includes `admin@weafrica.test`.
- If the Firebase users already exist, you can omit `TEST_ACCOUNT_PASSWORD`.

## What goes where (checklist)

- Local dev (Next.js): set in `.env.local`.
- Vercel (Next.js runtime): set in **Vercel → Project → Settings → Environment Variables**.
- Supabase DB schema/RLS: commit SQL migrations under `supabase/migrations/`, then apply with `supabase db push --include-all`.
- Supabase Edge Functions env: set in **Supabase Dashboard → Edge Functions → api → Secrets** (or `supabase secrets set ...`).
- Firebase Auth allowed domains: set in **Firebase Console → Authentication → Settings → Authorized domains**.
- Firestore security rules: update `firestore.rules` and deploy from your Firebase tooling (separately from Vercel/Supabase).

Required for admin access protection (middleware + session guard):

- `ADMIN_EMAILS` (comma-separated allowlist)
- `ADMIN_GUARD_SECRET` (long random secret used to sign/verify the `admin_guard` cookie)

Admin access control (RBAC):

- Admins are managed in the Supabase tables `public.admins` and `public.role_permissions`.
- Seed initial admins by editing `supabase/seed-admins.sql` (set real emails) and running migrations.
- On login, Firebase session is mapped to an admin row. Status must be `active`.
- Roles: `super_admin`, `operations_admin`, `finance_admin`, `support_admin` with least-privilege permissions.

Supabase admin writes + audit logs:

- Set `SUPABASE_SERVICE_ROLE_KEY` so admin actions can reliably write under RLS and record to `admin_logs` / `admin_activity`.

Subscriptions (PayChangu + renewals automation):

- `PAYCHANGU_SECRET_KEY` (PayChangu secret key; enables real Standard Checkout sessions in `POST /api/paychangu/start`)
- `PAYCHANGU_WEBHOOK_SECRET` (used to verify `POST /api/webhooks/paychangu`)
- `SUBSCRIPTIONS_CRON_SECRET` (shared secret header `x-cron-secret` for `POST /api/cron/subscriptions/expire`)

Subscriptions DB schema:

- Apply DB migrations (preferred): `supabase db push --include-all` (includes `subscription_plans` + `user_subscriptions`).
- If you’re bootstrapping manually in the Supabase SQL editor, ensure your schema includes the **SUBSCRIPTIONS** block in [minimal-supabase-schema.sql](minimal-supabase-schema.sql).

Featured Artists suggestions (optional “free AI” reranking via Hugging Face):

- `HUGGINGFACE_API_KEY` (server-only; create a free Hugging Face token)
- `HUGGINGFACE_FEATURED_ARTISTS_MODEL` (server-only; e.g. `mistralai/Mistral-7B-Instruct-v0.3`)

If these aren’t set, the “Suggest” button falls back to the built-in heuristic ranker.

## Deploy on Vercel (Always Online)

1) Push this repo to GitHub.

2) Vercel → **New Project** → import the repo → Deploy.

3) Vercel → Project → **Settings → Environment Variables**

Set these (at least for **Production**; usually also **Preview**):

- Backend:
	- `ADMIN_BACKEND_BASE_URL` (Vercel Preview deployments run with `NODE_ENV=production`, so you must set this for Preview too if you want admin pages to load)

- Supabase:
	- `NEXT_PUBLIC_SUPABASE_URL`
	- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
	- `SUPABASE_SERVICE_ROLE_KEY` (required for most admin writes/finance/ops under RLS)
- Admin protection:
	- `ADMIN_EMAILS`
	- `ADMIN_GUARD_SECRET`
- Firebase (client login):
	- `NEXT_PUBLIC_FIREBASE_API_KEY`
	- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
	- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
	- Optional: `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`, `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`, `NEXT_PUBLIC_FIREBASE_APP_ID`
- Firebase Admin (server-only) – choose exactly one:
	- `FIREBASE_SERVICE_ACCOUNT_BASE64` (recommended on Vercel)
	- OR `FIREBASE_SERVICE_ACCOUNT_JSON`

Note: `FIREBASE_SERVICE_ACCOUNT_PATH` is mainly for local dev; Vercel won’t have your JSON file unless you upload it yourself.

4) Firebase Console → Authentication → Settings → **Authorized domains**

Add your Vercel domain(s), e.g.:

- `your-project.vercel.app`
- Your custom domain (if any)

5) Redeploy after env var changes (Vercel → Deployments → Redeploy).

If admin login fails with `auth/api-key-not-valid`:

- Confirm `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`, `NEXT_PUBLIC_FIREBASE_PROJECT_ID` are set on Vercel for the same environment (Preview vs Production) and you redeployed.
- If the Firebase Web API key is restricted in Google Cloud Console, allow the Identity Toolkit API and add your Vercel domain to allowed HTTP referrers.

If admin login fails with "Invalid token" after entering correct credentials:

- This usually means Firebase Admin (server) is verifying tokens for a different project than the client is using.
- Set `FIREBASE_SERVICE_ACCOUNT_BASE64` (or `FIREBASE_SERVICE_ACCOUNT_JSON`) on Vercel to a service account from the same Firebase project as `NEXT_PUBLIC_FIREBASE_PROJECT_ID`, then redeploy.

## Supabase Edge Functions (api)

This repo includes a Supabase Edge Function named `api` in `supabase/functions/api`.

Supabase Edge Functions do **not** read Vercel env vars — they have their own Secrets/Env.

To fix missing Firebase project id inside the deployed function, set:

- `FIREBASE_PROJECT_ID=weafrica-music-85cdc`

Optional but recommended (locks down `/api/diag` in production):

- `WEAFRICA_DEBUG_DIAG_TOKEN=<random-long-string>`

### Option A: Supabase Dashboard

Supabase Dashboard → **Edge Functions** → `api` → **Secrets** → add/update `FIREBASE_PROJECT_ID`.

### Option B: Supabase CLI

1) Ensure you’re linked to the correct Supabase project:

```bash
supabase link --project-ref <your-project-ref>
```

2) Set the secret:

```bash
supabase secrets set FIREBASE_PROJECT_ID=weafrica-music-85cdc
```

Optional:

```bash
supabase secrets set WEAFRICA_DEBUG_DIAG_TOKEN="$(node -e \"console.log(require('crypto').randomBytes(24).toString('hex'))\")"
```

3) Redeploy (or restart) the function so the new env is applied:

```bash
supabase functions deploy api --no-verify-jwt
```

### Step 13 tip (Edge Function sanity)

If an endpoint is returning `401` unexpectedly, check the deployed function health first:

```bash
BASE_URL="https://<ref>.functions.supabase.co"
curl -sS "$BASE_URL/api/diag" \
	-H "x-debug-token: <WEAFRICA_DEBUG_DIAG_TOKEN>"
```

Notes:

- In production, `/api/diag` is hidden unless you set the Supabase Edge Function secret `WEAFRICA_DEBUG_DIAG_TOKEN` (or enable test routes).
- Response includes `firebase_project_id` and `firebase_expected_issuer` to quickly spot project/issuer mismatches.

You should see `has_firebase_project_id=true` and `has_service_role_key=true` for most routes.

If AI monetization endpoints return `500` (RPC/table missing), ensure your DB migrations are applied:

```bash
supabase db push --include-all
```

This should include the AI monetization + hardening migrations:

- `supabase/migrations/20260208120000_ai_monetization_core.sql`
- `supabase/migrations/20260208123000_ai_credit_ledger.sql`

## AI monetization smoke test (deployed Edge Function)

Run against your deployed base URL:

```bash
BASE_URL="https://<ref>.functions.supabase.co" bash tool/ai_monetization/smoke_test.sh
```

Notes:
- `GET /api/ai/pricing` is public.
- `GET /api/ai/balance` requires `ID_TOKEN` (Firebase Bearer token).
- `POST /api/beat/generate` requires `ID_TOKEN` by default (production). It will only run without Firebase auth if you explicitly enable dev-only test routes and set `TEST_TOKEN`.

## AI Beat Audio (MP3) jobs (Replicate + Storage)

Production endpoints (Firebase auth required):

- `POST /api/beat/audio/start`
- `GET /api/beat/audio/status?job_id=<uuid>`

This implements an async “start job → poll status → get signed `audio_url`” flow. The function uploads generated audio to a private Supabase Storage bucket (default `ai_beats`) and returns a signed URL when ready.

Required production steps:

1) Apply DB migrations:

```bash
supabase db push --include-all
```

2) Set Edge Function secrets (Supabase Dashboard → Edge Functions → `api` → Secrets):

- `REPLICATE_API_TOKEN` (required to actually generate)
- `WEAFRICA_REPLICATE_MUSIC_MODEL` (optional; default `meta/musicgen`)
- `WEAFRICA_REPLICATE_MUSIC_VERSION` (optional; if set, uses versioned predictions)
- `WEAFRICA_AI_BEATS_BUCKET` (optional; default `ai_beats`)

3) Redeploy the function:

```bash
supabase functions deploy api --no-verify-jwt
```

Tip: `GET /api/diag` exposes `has_replicate_api_token` so you can sanity-check secrets are present.

### Get a Firebase ID token locally (safe)

This prints an ID token to stdout using Firebase’s REST sign-in (keeps secrets on your machine).

```bash
FIREBASE_WEB_API_KEY="..." FIREBASE_EMAIL="you@example.com" FIREBASE_PASSWORD="your-password" \
	node tool/ai_monetization/get-firebase-id-token.mjs
```

Compatibility wrappers:
- `node get-firebase-id-token.mjs` (repo root)
- `node scripts/get-firebase-id-token.mjs`

Then run the smoke test (without pasting the token into chat):

```bash
BASE_URL="https://<ref>.functions.supabase.co" \
	ID_TOKEN="$(FIREBASE_WEB_API_KEY="..." FIREBASE_EMAIL="you@example.com" FIREBASE_PASSWORD="your-password" node tool/ai_monetization/get-firebase-id-token.mjs)" \
	bash tool/ai_monetization/smoke_test.sh
```

Notes:
- The token is never printed unless you explicitly `echo` it.
- If you already have `NEXT_PUBLIC_FIREBASE_API_KEY` in `.env.local`, you can omit `FIREBASE_WEB_API_KEY`.

### Dev-only: TEST_TOKEN

If the deployed function has `WEAFRICA_ENABLE_TEST_ROUTES=true` and a configured `WEAFRICA_TEST_TOKEN`, you can run generation tests without Firebase auth:

```bash
BASE_URL="https://<ref>.functions.supabase.co" TEST_TOKEN="<weafrica_test_token>" bash tool/ai_monetization/smoke_test.sh
```

Security:
- Treat `ID_TOKEN` and `TEST_TOKEN` as secrets; don’t paste them into issues/logs.
- If a token leaks, rotate the underlying credential (and/or change `WEAFRICA_TEST_TOKEN`).

Production must-do:
- For real production, disable test routes: unset (or set `WEAFRICA_ENABLE_TEST_ROUTES=false`) and remove `WEAFRICA_TEST_TOKEN`, then redeploy.
- Confirm via `GET /api/diag` that `enable_test_routes=false` and `has_test_token=false`.

Notes:
- If the function also needs to call Supabase as an admin, set `SUPABASE_SERVICE_ROLE_KEY` as a Function secret too.
- If your function is building PayChangu checkout URLs, set `PAYCHANGU_CHECKOUT_URL` / `PAYCHANGU_CHECKOUT_URL_<PLANID>` as Function secrets.

### Agora RTC token endpoint (consumer live)

This repo’s Supabase Edge Function `api` also exposes:

- `POST /api/agora/token`

It generates an Agora RTC token for a given `channel_id` (e.g. `live_<artist_id>`), so the consumer app can join live without pasting tokens manually.

Required Function secrets (Supabase Dashboard → Edge Functions → `api` → Secrets):

- `AGORA_APP_ID`
- `AGORA_APP_CERTIFICATE` (keep secret)

Auth behavior:

- If `FIREBASE_PROJECT_ID` is set, the endpoint requires `Authorization: Bearer <Firebase ID token>`.
- If Firebase isn’t configured, it only allows test access when `WEAFRICA_ENABLE_TEST_ROUTES=true` and header `x-weafrica-test-token` matches `WEAFRICA_TEST_TOKEN`.

Deploy (example):

```bash
supabase functions deploy api --no-verify-jwt
```

## Live smoke test (deployed Edge Function)

This repo’s deployed Supabase Edge Function `api` currently exposes Live-critical routes:

- `GET /api/diag`
- `POST /api/agora/token`
- `GET /api/battle/status`
- `POST /api/battle/ready`

Before running, ensure:

- DB migrations are applied (at minimum `supabase/migrations/20260111113000_live_streams.sql`, plus any newer Live migrations you have locally):

```bash
supabase db push --include-all
```

- Edge Function secrets are set:
	- `FIREBASE_PROJECT_ID`
	- `SUPABASE_SERVICE_ROLE_KEY`
	- `AGORA_APP_ID`
	- `AGORA_APP_CERTIFICATE`

- Production hardening: `WEAFRICA_ENABLE_TEST_ROUTES` is **unset** (or `false`) and `WEAFRICA_TEST_TOKEN` is removed.

Run against your deployed Function base URL:

```bash
BASE_URL="https://<ref>.functions.supabase.co" bash tool/live/smoke_live.sh
```

Optional inputs:

- `CHANNEL_ID` (defaults to `weafrica_live_smoke`)
- `BATTLE_ID` (to exercise `/api/battle/status` and `/api/battle/ready`)
- `ID_TOKEN` (required in production to test publisher token + battle ready)

Example with Firebase auth:

```bash
BASE_URL="https://<ref>.functions.supabase.co" \
	ID_TOKEN="$(FIREBASE_WEB_API_KEY="..." FIREBASE_EMAIL="you@example.com" FIREBASE_PASSWORD="your-password" node tool/ai_monetization/get-firebase-id-token.mjs)" \
	CHANNEL_ID="weafrica_battle_smoke" \
	BATTLE_ID="123" \
	bash tool/live/smoke_live.sh
```

### Smoke test against Vercel (no local server)

You can run the smoke scripts from your machine while targeting your deployed Vercel URL.

- Consumer integration (ads config + DB round-trip + optional events ingest):
	- `SMOKE_BASE_URL=https://<your-app>.vercel.app node scripts/smoke-consumer-integration.mjs`
- Consumer subscriptions end-to-end (PayChangu webhook -> `/api/subscriptions/me`):
	- `SMOKE_BASE_URL=https://<your-app>.vercel.app node scripts/smoke-subscription-consumer.mjs`

Notes:
- These scripts still read secrets from your local `.env.local` (Firebase Admin creds, `PAYCHANGU_WEBHOOK_SECRET`, Supabase keys) but the HTTP requests go to Vercel.
- Make sure your Vercel environment has the same server-side secrets set (especially `SUPABASE_SERVICE_ROLE_KEY` and `PAYCHANGU_WEBHOOK_SECRET`) for the deployment you’re testing (Preview vs Production).

### Admin Bootstrap (Supabase)

After deployment, your Firebase login must map to a row in Supabase before you can access `/admin`.

1) Apply the admin RBAC migrations to your Supabase project:

- Run the SQL files in `supabase/migrations/` (recommended)
- Or at minimum ensure these exist:
	- `public.admins`
	- `public.role_permissions`
	- `public.admins_with_permissions`

2) Create (or upsert) your admin user row:

- Recommended (uses `SUPABASE_SERVICE_ROLE_KEY` from `.env.local`):

```bash
npx ts-node supabase/seed-admin-profile.ts <your-admin-email> super_admin
```

- Or run SQL in Supabase SQL Editor:

```sql
insert into public.admins (email, role, status)
values ('<your-admin-email>', 'super_admin', 'active')
on conflict (email) do update set role = excluded.role, status = excluded.status;
```

3) Reload the admin page.

### Creator approval + content publishing (SQL)

If you need to manually approve creator accounts or publish content (typically to satisfy RLS requirements), run the following in the Supabase SQL Editor (or via a server-side script using the service-role key):

```sql
-- Check permission (server-side)
select * from public.admins_with_permissions
where email = '<your-admin-email>' and status = 'active'
limit 1;

-- Approve / block creators
update public.artists set approved=true, status='active'
where user_id='FIREBASE_UID' or firebase_uid='FIREBASE_UID';

update public.djs set approved=true, status='active'
where firebase_uid='FIREBASE_UID';

-- Publish content (your RLS requires BOTH approved + is_active for songs/videos)
update public.songs  set approved=true, is_active=true where id='SONG_UUID'::uuid;
update public.videos set approved=true, is_active=true where id='VIDEO_UUID'::uuid;
```

### Troubleshooting “Admin access not configured”

If you can sign in but still see the “Admin access not configured” screen:

- Confirm `SUPABASE_SERVICE_ROLE_KEY` is set on Vercel for the environment you’re using (**Production** vs **Preview**).
- Make sure keys are pasted as a single line (no quotes/newlines) and match the same Supabase project as `NEXT_PUBLIC_SUPABASE_URL`.
- After changing env vars, redeploy.

Note: `/api/admin/supabase-env-debug` is disabled in production (returns 404). Use it only in local dev / preview deployments.

Security: never paste service role keys in issues/screenshots. Rotate the key in Supabase if it’s ever exposed.

### Production safety notes

- `SUPABASE_SERVICE_ROLE_KEY` is required in production; the server will fail fast if it’s missing/placeholder.
- Debug/test endpoints are disabled in production (e.g. `/api/admin/supabase-env-debug`, `/api/admin/finance/test`).

Run migrations locally (requires Supabase CLI):

```bash
supabase start
supabase db push
```

If you don't run Docker locally, apply the SQL in your Supabase project SQL editor.

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Monitoring, Backups & Audit

### Sentry (Next.js Admin)
- Install: `npm i @sentry/nextjs`
- Create `sentry.client.config.ts` / `sentry.server.config.ts` (standard init) and set `NEXT_PUBLIC_SENTRY_DSN` / `SENTRY_DSN`.
- In `next.config.ts`, wrap export with `withSentryConfig` (see comment in file).

### Admin Audit Logs
- Table: `public.admin_audit_logs` via migration at `supabase/migrations/20260111190000_admin_audit_logs.sql`.
- Helper: `src/lib/admin/audit.ts` (server-only). Use `logAdminAction({...})` in admin flows.
- Login/Logout are logged by `POST/DELETE /api/auth/session`.

### Health Overview
- Admin page at `/admin/health` shows basic connectivity and counters. Extend with more metrics over time.

### Backups
- Ensure Supabase automated backups are enabled (project settings).
- Weekly manual exports: `./scripts/backup.sh` (requires Supabase CLI). Output is written under `backups/`.

### Environment
Set these in `.env.local`:

```bash
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=... # required for audit logging

# Optional Sentry
SENTRY_DSN=...
NEXT_PUBLIC_SENTRY_DSN=...
```

## Country-Based Rules & Localization

- DB: `public.countries` with deny-all RLS. Migration: `supabase/migrations/20260111190500_countries_core.sql`.
- Malawi defaults seeded (MW, MWK, coin_rate 1800, mobile money methods).
- Country code columns added to `transactions` and `withdrawals` (migration: `20260111190600_add_country_columns.sql`).
- Admin country selector in the top bar writes an `admin_country` cookie via `POST /api/admin/country`.
- Helpers: `src/lib/country/context.ts` provides `getAdminCountryCode()` and `getCountryConfigByCode()` and a simple `convertUsdToCoins()`.

Apply migrations locally:

```bash
supabase start
supabase db push
```


## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
