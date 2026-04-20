# Consumer subscriptions setup

This admin repo already contains the canonical plan IDs and the server-side plumbing that updates subscription state after payments.

## 1) Plan IDs (what the consumer app should use)

Plans are identified by `plan_id`.

The default plan catalog + entitlements are defined here:
- src/lib/subscription/plans.ts

Default IDs:
- `free`
- `premium`
- `premium_weekly`
- `platinum`
- `platinum_weekly`

Recommended behaviors:
- `free`: ads enabled (interstitial cadence via entitlements), no downloads, no playlist creation
- `premium`: no ads + unlimited skips + background play + downloads (offline) + high audio quality (up to 320 kbps) + create playlists + watch live artists/DJs + watch battles + cancel anytime
- `platinum`: everything in premium + studio audio quality (up to 24-bit / 44.1 kHz) + playlist mixing + personal AI DJ + priority battles + battle replays anytime + cancel anytime
	- `platinum`: 200 free coins / month
	- `platinum_weekly`: 50 free coins / week

Recommended pricing defaults (MWK):
- Malawi monthly: `premium` = 5,000; `platinum` = 8,500
- Malawi weekly: `premium_weekly` = 1,250; `platinum_weekly` = 2,125

In the consumer app, treat `plan_id` as the only stable identifier (do not rely on plan names).

## 2) Fetch plans (pricing catalog)

Because Supabase tables are RLS deny-all, the consumer app should not query `subscription_plans` directly.

Use the public API endpoint:
- GET `/api/subscriptions/plans`

Optional query params:
- `audience=consumer|artist|dj` (default: `consumer`)

Response:
- `{ ok: true, source: 'db' | 'fallback', interval_count, plans: [{ plan_id, name, price_mwk, billing_interval, total_price_mwk, interval_count }] }`

Pricing semantics:
- `price_mwk` is the **per-interval** price (1 week or 1 month, depending on `billing_interval`).
- `interval_count` controls how many intervals the user is buying.
- `total_price_mwk = price_mwk * interval_count`.

Optional query params:
- `interval_count=<n>` (defaults to `1`)
- Backward-compatible alias: `months=<n>`

Notes:
- If `subscription_plans` is missing or empty, the endpoint returns `source=fallback` using the defaults from `src/lib/subscription/plans.ts` (so you still get Free/Premium/Platinum during initial setup).

Implementation:
- src/app/api/subscriptions/plans/route.ts

## 3) Start a subscription payment

### Consumer app config (PayChangu kickoff)

The consumer app needs the backend base URL and a PayChangu kickoff endpoint to start a checkout:

- Base URL: already supported via `--dart-define=WEAFRICA_API_BASE_URL=...` (or the asset env file, depending on how you ship config).
	- Known working production base URL (Feb 2026): `https://weafrica-admin-dashboard.vercel.app`
	- NOTE: `https://weafrica-music-admin.vercel.app` currently returns `DEPLOYMENT_NOT_FOUND` (404) on Vercel unless an alias + production deployment is configured.
- PayChangu start path: set `WEAFRICA_PAYCHANGU_START_PATH` in `supabase.env.json` (copy from `supabase.env.json.example`) to the backend route that creates a PayChangu payment and returns a `checkout_url`.

The kickoff request should include metadata (so the webhook can reconcile the payment back to a user + plan):
- `user_id` (Firebase `uid`)
- `plan_id` (e.g. `premium`)
- `interval_count` (e.g. `1`) — how many weeks/months to buy
- Backward-compatible alias: `months` (treated as interval count)
- `country_code` (e.g. `MW`)

Expected kickoff response shape:
- `{ checkout_url: string }`

Notes:
- Preferred: `POST /api/paychangu/start` with JSON body.
- Backward-compatible: `GET /api/paychangu/start?plan_id=..&user_id=..&months=..` is also supported in the Supabase Edge Function for clients that accidentally call it as GET.

### Production (real checkout) mode

In production, `/api/paychangu/start` can create a real PayChangu Standard Checkout session (recommended) when these server env vars are set:

- `PAYCHANGU_SECRET_KEY` (PayChangu secret key; used as `Authorization: Bearer ...`)
- `PAYCHANGU_WEBHOOK_SECRET` (for validating the webhook `Signature` header)

Optional (but recommended) URLs:

- `PAYCHANGU_CALLBACK_URL` (defaults to `${BASE_URL}/api/paychangu/callback`)
- `PAYCHANGU_RETURN_URL` (defaults to `${BASE_URL}/`)

Notes:
- PayChangu will redirect the user to `callback_url` after payment and also call your webhook URL if enabled.
- The webhook endpoint in this repo is `POST /api/webhooks/paychangu`.
- For extra safety, PayChangu recommends verifying transactions server-side via `GET https://api.paychangu.com/verify-payment/{tx_ref}` before granting value.

Payments are processed via PayChangu webhooks. The webhook handler expects the payment initiation to include metadata.

Webhook endpoint (server-side):
- POST `/api/webhooks/paychangu`

DB requirement:
- The table `public.subscription_payments` must exist (migration: `supabase/migrations/20260115120000_paychangu_subscriptions.sql`).
- If you see a Supabase error like “Could not find the table ... in the schema cache”, it usually means the migration hasn’t been applied yet (or PostgREST needs a schema cache refresh).
- If you see: “Could not find the '<col>' column of 'paychangu_payments' in the schema cache” (e.g. `months`, `raw`, `tx_ref`), you’re on a legacy schema. Apply the compatibility migration `supabase/migrations/20260209121000_paychangu_payments_legacy_columns.sql` (or add the columns manually) and re-try.

When you create a PayChangu payment in the consumer app (or via your consumer backend), include these metadata fields:
- `plan_id` (string; e.g. `premium`)
- `user_id` (string; Firebase `uid`)
- `interval_count` (number; default `1`)
- Backward-compatible alias: `months` (treated as interval count)
- `country_code` (optional; default `MW`)

On `status=paid`, the webhook:
- upserts a row in `subscription_payments`
- activates or extends `user_subscriptions`
- creates a `transactions` ledger entry of type `subscription`

Duration semantics:
- If the plan `billing_interval` is `month`, the webhook extends `ends_at` by `interval_count` months.
- If the plan `billing_interval` is `week`, the webhook extends `ends_at` by `interval_count * 7` days.

Source:
- src/app/api/webhooks/paychangu/route.ts

## 4) Read subscription status in the consumer app

`user_subscriptions` is RLS deny-all in the migrations, so the consumer app should not read it directly.

Use the Firebase-authenticated endpoint:
- GET `/api/subscriptions/me`

Auth:
- header `Authorization: Bearer <firebase_id_token>`

This returns:
- the user’s current active subscription (if any)
- the current plan and computed entitlements

Implementation:
- src/app/api/subscriptions/me/route.ts

Ads gating recommendation (Free plan):
- Call `/api/subscriptions/me` to get `entitlements`
- Optionally also call `/api/ads/config?country_code=..&plan_id=..` to respect the country ops toggle
- If ads are enabled:
	- Songs: use `entitlements.perks.ads.interstitial_every_songs` (defaults to `3`) to show an interstitial after every N songs
	- Videos: use `entitlements.perks.ads.interstitial_every_videos` (defaults to `2`) to show an interstitial after every N videos

Free gating recommendation:
- Playlists: only allow “Create playlist” if `entitlements.perks.playlists.create === true`
- Downloads: only allow downloads if `entitlements.perks.downloads.enabled === true`

Token claims (optional optimization):
- The backend best-effort syncs Firebase custom claims on subscription changes:
	- `sub_plan` (e.g. `premium`)
	- `sub_status` (e.g. `active`)
	- `sub_ends_at` (ISO string, when known)
- Source of truth remains `/api/subscriptions/me` (claims can be stale until token refresh).

Alternative:
- If you prefer direct Supabase reads, add a strict RLS policy that allows a user to `select` only their own rows (requires Supabase Auth, not Firebase).

## 5) Expiry cron

Subscriptions expire via a cron route:
- POST `/api/cron/subscriptions/expire`

It requires:
- `SUBSCRIPTIONS_CRON_SECRET` env var
- header `x-cron-secret: <value>`

Source:
- src/app/api/cron/subscriptions/expire/route.ts

## 6) Promotions + ads flags (already public)

Useful public endpoints for the consumer app:
- GET `/api/subscriptions/promotions?plan_id=...`
- GET `/api/ads/config?country_code=MW&plan_id=premium`

Sources:
- src/app/api/subscriptions/promotions/route.ts
- src/app/api/ads/config/route.ts
