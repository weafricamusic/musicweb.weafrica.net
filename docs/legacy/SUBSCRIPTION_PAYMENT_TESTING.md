# Subscription + Payment Testing (PayChangu)

This repo’s Flutter app uses a backend API for subscriptions:

- `GET /api/subscriptions/plans` (public)
- `GET /api/subscriptions/me` (Firebase-authenticated)
- `POST /api/paychangu/start` (Firebase-authenticated)

A Supabase Edge Function is included at [supabase/functions/api/index.ts](supabase/functions/api/index.ts) that provides these routes.

## 1) Backend setup (Supabase Edge Function)

### Deploy

From your Supabase project directory:

- `supabase functions deploy api --no-verify-jwt`

### Required function env vars

Set these on the deployed Edge Function:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (required for `GET /api/subscriptions/me`)
- `FIREBASE_PROJECT_ID` (required to verify Firebase ID tokens)

### Optional (PayChangu checkout URL)

For basic “start payment opens browser” testing without integrating PayChangu APIs yet, set one of:

- `PAYCHANGU_CHECKOUT_URL` (used for all plans)
- `PAYCHANGU_CHECKOUT_URL_PREMIUM`, `PAYCHANGU_CHECKOUT_URL_PLATINUM`, etc.

> If these are not set, `POST /api/paychangu/start` returns a `501 not_implemented` error.

### Real PayChangu (recommended)

The Edge Function supports PayChangu Standard Checkout and webhooks.

Set these on the Edge Function:

- `PAYCHANGU_SECRET_KEY` (test or live)
- `PAYCHANGU_WEBHOOK_SECRET` (from PayChangu dashboard)

Webhook URL to configure in PayChangu dashboard:

- `https://<project-ref>.functions.supabase.co/api/paychangu/webhook`

PayChangu requires `callback_url` and `return_url` when initiating a transaction.
If you don’t set them explicitly, the function derives:

- `https://<project-ref>.functions.supabase.co/api/paychangu/callback`
- `https://<project-ref>.functions.supabase.co/api/paychangu/return`

### Apply DB migrations

Apply migrations in [supabase/migrations](supabase/migrations):

- `subscription_plans` (plan catalog)
- `user_subscriptions` (per-user active plan/status)

## 2) App setup (Flutter)

Configure the API base URL to point to the Supabase Functions origin:

- `WEAFRICA_API_BASE_URL=https://<project-ref>.functions.supabase.co`

Also ensure:

- `WEAFRICA_PAYCHANGU_START_PATH=/api/paychangu/start`

You can set these either via `--dart-define` or by editing `assets/config/supabase.env.json` (see `assets/config/supabase.env.json.example`).

## 3) Recommended end-to-end test flow

### A. Validate catalog loads

1. Run the app and open the Upgrade screen.
2. Confirm plans appear (Premium/Platinum).

If plans don’t load:
- Verify `WEAFRICA_API_BASE_URL` is correct.
- Ensure the Edge Function is deployed.
- Check that the `subscription_plans` migration ran.

### B. Validate payment “start” opens checkout

1. Tap Upgrade on a paid plan.
2. App calls `POST /api/paychangu/start` and opens the returned `checkout_url`.

If you get errors:
- Ensure `PAYCHANGU_CHECKOUT_URL` (or plan-specific one) is set on the Edge Function.
- Ensure `FIREBASE_PROJECT_ID` is set and the user is logged in.

### C. Validate subscription activation (sandbox, no real charge)

The Edge Function includes a **test-only activation** route:

- `POST /api/subscriptions/test/activate`

Enable it by setting on the Edge Function:

- `WEAFRICA_ENABLE_TEST_ROUTES=true`
- Optional: `WEAFRICA_TEST_TOKEN=<secret>`

If you set `WEAFRICA_TEST_TOKEN`, also set the same value in the app config (`assets/config/supabase.env.json`) as `WEAFRICA_TEST_TOKEN`.

Then in the app (Debug builds only):

1. Open Upgrade screen.
2. Use **Debug: simulate payment** → **Activate Premium/Platinum**.
3. Tap **Refresh access** (or wait for the automatic poll).

Expected:
- `GET /api/subscriptions/me` returns `status=active` and `plan_id=premium|platinum`.
- The UI updates and any entitlement gating (ads/offline/etc.) can be verified.

## Notes / next step for real payments

Real PayChangu webhook reconciliation is implemented in the Edge Function:

- Initiation: `POST /api/paychangu/start`
- Webhook: `POST /api/paychangu/webhook` (HMAC signature + verify-payment requery)
- Activation: updates `user_subscriptions` after a verified successful payment

If you want *exact* month arithmetic (calendar months instead of 30-day blocks), I can switch the subscription extension logic to use a DB-side interval update.
