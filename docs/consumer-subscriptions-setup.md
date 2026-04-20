# Subscriptions (Firebase Auth) — Consumer + Creator (Artist/DJ) wiring

This app uses **Firebase Auth** for user identity.
Your backend API expects the **Firebase ID token** in the `Authorization` header.

Listener vs creator is driven by the plan catalog you load:
- Listener plans: `audience=consumer`
- Artist plans: `audience=artist`
- DJ plans: `audience=dj`
- Legacy combined creator catalog: `audience=creator` (compatibility alias that returns Artist + DJ launch rows)

## 1) Base URL

### Production (API origin)

For production, set the consumer app to your public API origin (no Vercel required).

Endpoints used by the consumer app:

- `GET /api/subscriptions/plans`
- `POST /api/paychangu/start`
- `GET /api/subscriptions/me` (Firebase ID token required)

If you're using Supabase Edge Functions (recommended in this repo), deploy the Edge Function named `api` and point the Flutter app at the Supabase Functions domain.

Deploy:

```bash
supabase functions deploy api --no-verify-jwt
```

Then set:

- `WEAFRICA_API_BASE_URL=https://<your-project-ref>.functions.supabase.co`

This makes Flutter requests like `GET /api/subscriptions/plans` hit the Edge Function at:

- `https://<ref>.functions.supabase.co/api/subscriptions/plans`

The Flutter app already supports a configurable backend base URL via `ApiEnv`.

- Prefer: `--dart-define=WEAFRICA_API_BASE_URL=https://<your-domain>`
- Or for local dev: set `WEAFRICA_API_BASE_URL` in `assets/config/supabase.env.json`

See: [lib/app/config/api_env.dart](../lib/app/config/api_env.dart)

## 2) Fetch plan catalog (pricing)

Backend endpoint:
- Listener catalog: `GET /api/subscriptions/plans?audience=consumer&interval_count=1`
- Artist catalog: `GET /api/subscriptions/plans?audience=artist&interval_count=1`
- DJ catalog: `GET /api/subscriptions/plans?audience=dj&interval_count=1`
- Legacy combined creator catalog: `GET /api/subscriptions/plans?audience=creator&interval_count=1`

Backward-compatible param (older backends):
- `months=1`

Notes:
- Treat `plan_id` as the stable identifier (do not key off the display `name`).
- Response includes a `source` field:
  - `"db"` after you apply the Supabase migration(s)
  - `"env"` if you configured `WEAFRICA_PLANS_JSON` on the Edge Function
  - `"fallback"` if neither DB nor env is configured

Flutter/Dart example:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:weafrica_music/app/config/api_env.dart';

Future<List<dynamic>> fetchPlans() async {
  final uri = Uri.parse('${ApiEnv.baseUrl}/api/subscriptions/plans?audience=consumer');
  final res = await http.get(uri, headers: {'Accept': 'application/json'});

  if (res.statusCode != 200) {
    throw Exception('Failed to fetch plans: HTTP ${res.statusCode} ${res.body}');
  }

  final decoded = jsonDecode(res.body);
  // Adjust shape to match your backend response.
  if (decoded is Map && decoded['plans'] is List) return decoded['plans'] as List;
  if (decoded is List) return decoded;
  return const [];
}
```

## 2.1) Creator plans (Artist + DJ)

Fetch creator plans exactly like consumer plans, but prefer the role-specific audience:

- Artist: `audience=artist`
- DJ: `audience=dj`

`audience=creator` still works as a compatibility alias when you want both launch catalogs in one response.

Notes for this repo’s backend:
- The Supabase Edge Function accepts `consumer`, `artist`, `dj`, and `creator`.
- Public catalogs are launch-only and monthly-only.
- Legacy weekly/shared creator aliases are filtered out of the public catalog.

Seeded creator plan IDs in this repo (via Supabase migrations):
- `artist_starter`
- `artist_pro`
- `artist_premium`
- `dj_starter`
- `dj_pro`
- `dj_premium`

Flutter example (preferred: use the existing API wrapper):

```dart
import 'package:weafrica_music/features/subscriptions/services/subscriptions_api.dart';

final artistPlans = await SubscriptionsApi.fetchPlans(audience: 'artist');
final djPlans = await SubscriptionsApi.fetchPlans(audience: 'dj');
```

## 2.2) Launch catalog (March 2026)

The current launch catalog is monthly-only, Malawi-priced, and uses these stable plan IDs:

### Listener plans

- `free` → **Free** → MWK 0
- `premium` → **Premium Listener** → MWK 4,000
- `platinum` → **VIP Listener** → MWK 8,500

Notes:

- `vip` is accepted as a compatibility alias for `platinum`.
- Keep the backend ID as `platinum`; only the display label changes to **VIP Listener**.

### Artist plans

- `artist_starter` → **Artist Starter** → MWK 0
- `artist_pro` → **Artist Pro** → MWK 8,000
- `artist_premium` → **Artist Premium** → MWK 12,000

### DJ plans

- `dj_starter` → **DJ Starter** → MWK 0
- `dj_pro` → **DJ Pro** → MWK 7,000
- `dj_premium` → **DJ Premium** → MWK 11,000

Launch notes:

- Weekly rows and shared creator aliases (`starter`, `pro`, `elite`, `*_weekly`) remain compatibility-only and should not be shown in launch catalogs.
- The 30-day Artist Pro / DJ Pro launch offer is handled manually through the admin subscription tools; it is **not** an automated trial system.
- Broader Africa-wide dynamic pricing is deferred for now because the current schema still stores a single `price_mwk` per plan.

## 3) Get current subscription (requires Firebase ID token)

Backend endpoint:
- `GET /api/subscriptions/me`

Headers:
- `Authorization: Bearer <firebase_id_token>`

Flutter/Dart example:

```dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:weafrica_music/app/config/api_env.dart';

Future<Map<String, dynamic>> fetchMySubscription() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not logged in');

  final idToken = await user.getIdToken();
  final uri = Uri.parse('${ApiEnv.baseUrl}/api/subscriptions/me');

  final res = await http.get(
    uri,
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $idToken',
    },
  );

  if (res.statusCode != 200) {
    throw Exception('Failed to fetch subscription: HTTP ${res.statusCode} ${res.body}');
  }

  final decoded = jsonDecode(res.body);
  return (decoded is Map<String, dynamic>) ? decoded : <String, dynamic>{};
}
```

## 4) Initiate PayChangu payment (metadata contract)

When the app initiates a PayChangu payment, call your backend and include the fields the webhook expects.

Recommended request body (POST):

```json
{
  "plan_id": "premium",
  "interval_count": 1,
  "months": 1,
  "country_code": "MW",
  "user_id": "firebase_uid_here"
}
```

Recommended response (200):

```json
{ "checkout_url": "https://checkout.paychangu.com/..." }
```

Optional but helpful for debugging/idempotency:

```json
{ "checkout_url": "...", "provider_reference": "tx_ref_or_transaction_id" }
```

Notes:
- Your backend webhook will activate/extend `user_subscriptions`.
- After returning to the app, refresh (or poll) `GET /api/subscriptions/me` until it shows the plan as active.

Security:
- Do NOT put `PAYCHANGU_SECRET_KEY`, `PAYCHANGU_WEBHOOK_SECRET`, or any webhook signing secrets in Flutter.
  Flutter should only call your backend and open the returned `checkout_url`.

## 4.1) Real PayChangu wiring (server-side + webhooks)

This repo’s Supabase Edge Function implements PayChangu **Standard Checkout** and a secure webhook:

- `POST /api/paychangu/start` → calls `POST https://api.paychangu.com/payment` and returns `checkout_url`
- `POST /api/paychangu/webhook` → validates `Signature` (HMAC-SHA256), then calls `GET https://api.paychangu.com/verify-payment/{tx_ref}` before activating the user.

### Edge Function env vars (required)

Set these on the deployed Edge Function:

- `PAYCHANGU_SECRET_KEY` (test or live key)
- `PAYCHANGU_WEBHOOK_SECRET` (from PayChangu dashboard)

Optional:

- `PAYCHANGU_API_BASE` (default: `https://api.paychangu.com`)
- `PAYCHANGU_CALLBACK_URL` (default: derived as `https://<your-functions-origin>/api/paychangu/callback`)
- `PAYCHANGU_RETURN_URL` (default: derived as `https://<your-functions-origin>/api/paychangu/return`)

### Configure webhook on PayChangu dashboard

In PayChangu dashboard → Settings → API Keys & Webhooks, set the webhook URL to:

- `https://<your-project-ref>.functions.supabase.co/api/paychangu/webhook`

Then, when a payment succeeds, the webhook will update:

- `public.paychangu_payments` (ledger)
- `public.user_subscriptions` (activates/extends access)

## 5) Recommended UI flow

- Show plan list (from `/api/subscriptions/plans`)
- User taps a plan → start payment → show “processing”
- On success/return → call `/api/subscriptions/me`
- Gate premium UI based on the response

For role-specific entry points, the app already includes:
- `RoleBasedSubscriptionScreen` → chooses Listener vs Creator catalog.
- `SubscriptionScreen` → renders the catalog and triggers PayChangu checkout.

## 6) Debug checklist

- Confirm `WEAFRICA_API_BASE_URL` is reachable from device (LAN IP for physical devices).
- Confirm Firebase user is logged in and `getIdToken()` returns a non-empty token.
- Confirm backend validates token and can resolve `user_id`.
- If you see 401/403: token verification on backend is failing (wrong Firebase project/service account/etc.).

## 7) Make plans live from Supabase DB

This repo ships a migration that creates/seeds `public.subscription_plans`. Once applied, `GET /api/subscriptions/plans?audience=consumer` should return `source: "db"`.

Apply migrations (pick one flow):

- Local dev:
  - `supabase db reset` (recreates DB from scratch), or
  - `supabase migration up`
- Hosted Supabase:
  - Run the newest SQL in `supabase/migrations/` via Supabase SQL editor, or
  - Apply via your CI migration pipeline
