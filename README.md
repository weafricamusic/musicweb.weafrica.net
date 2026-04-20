# weafrica_music

A new Flutter project.

## Admin Dashboard

This repo now includes the web admin dashboard as a separate Next.js app in `admin_dashboard/`.

- Install dashboard dependencies: `npm run admin:install`
- Bootstrap local env (creates `admin_dashboard/.env.local`, fills Firebase public vars, and copies Supabase URL/anon key from existing local config when available): `npm run admin:setup`
	- Set up Firebase Admin credentials for session cookies: `npm run admin:setup:firebase-admin -- --from-clipboard` (macOS) or `--from <path-to-json>`
	- Note: this creates `admin_dashboard/firebase-service-account.json` (gitignored).
	- Set up Supabase env + (optionally) service role key: `npm run admin:setup:supabase` then `npm run admin:setup:supabase -- --service-from-clipboard`
	- Sanity check: `npm --prefix admin_dashboard run check:firebase-admin`
- Start the dashboard locally: `npm run admin` (or `npm run admin:dev`)
- Build the dashboard: `npm run admin:build`
- Open the dashboard at `http://localhost:3000/auth/login`
- Environment setup and deployment details live in `admin_dashboard/README.md`

This integration is admin-only. Creator portal entry routes under `/artist` and `/dj` redirect to the admin login, and creator-only API namespaces under `/api/artist` and `/api/dj` are blocked.

## WE AFRICAN STAGE docs

- Product specification (v1): docs/WE_AFRICAN_STAGE_PLATFORM_SPEC_v1.md
- Technical architecture (v1): docs/WE_AFRICAN_STAGE_TECHNICAL_ARCHITECTURE_v1.md
- Build-ready spec (v1.1): docs/WE_AFRICAN_STAGE_BUILD_READY_v1_1.md

## WE AFRICA MUSIC docs

- Complete platform architecture: docs/WE_AFRICA_MUSIC_COMPLETE_PLATFORM_ARCHITECTURE.md

## Supabase setup

This app can initialize config via either:
- a bundled asset JSON file (easy local dev), or
- Dart defines / `--dart-define-from-file` (recommended for CI and reproducible builds).

### Option A: Use bundled asset env (quickest)

1. Copy the example asset file:
	- `cp assets/config/supabase.env.json.example assets/config/supabase.env.json`
2. Fill in:
	- `SUPABASE_URL`
	- `SUPABASE_ANON_KEY` (anon/public key only)
	- `WEAFRICA_API_BASE_URL`
	- `WEAFRICA_PAYCHANGU_START_PATH` (default: `/api/paychangu/start`)

Note: real PayChangu payments are configured on the backend (Supabase Edge Function) via env vars like `PAYCHANGU_SECRET_KEY` and `PAYCHANGU_WEBHOOK_SECRET`. See [docs/consumer-subscriptions-setup.md](docs/consumer-subscriptions-setup.md).

### Option B: Use Dart defines (recommended)

This app initializes Supabase at startup using Dart defines:

1. Copy the example file:
	- `cp tool/supabase.env.json.example tool/supabase.env.json`
2. Fill in values from Supabase Dashboard → Project Settings → API:
	- `SUPABASE_URL`
	- `SUPABASE_ANON_KEY` (anon/public key only)
3. Run with defines:
	- `flutter run --dart-define-from-file=tool/supabase.env.json`

### Seed demo data (tracks)

After creating the tables (see `tool/supabase_schema.sql`), insert at least one track so Home/Library have data.

- Run `tool/seed_tracks.sql` in Supabase SQL Editor.

### Fix Storage public URLs (songs)

If your `public.songs` rows contain Supabase Storage URLs without the `/public/` segment (or mixed thumbnail bucket naming), run:

- `tool/fix_public_storage_urls.sql` in Supabase SQL Editor.


In VS Code you can also use the bundled launch config “Flutter (Supabase)”.

## Step 13 — AI Monetization Engine

What goes where:

- SQL (tables/RPCs): see [supabase/migrations/20260207010000_ai_monetization_engine.sql](supabase/migrations/20260207010000_ai_monetization_engine.sql)
- SQL (hardening): see [supabase/migrations/20260208123000_ai_credit_ledger.sql](supabase/migrations/20260208123000_ai_credit_ledger.sql)
- Edge Function (TypeScript routes): [supabase/functions/api/index.ts](supabase/functions/api/index.ts)

Deploy notes + smoke test:

- [tool/ai_monetization/README.md](tool/ai_monetization/README.md)
- [tool/ai_monetization/smoke_test.sh](tool/ai_monetization/smoke_test.sh)

Tip: run the smoke test without `ID_TOKEN` to validate public endpoints; set `ID_TOKEN` to test `/api/ai/balance` and the monetized `/api/beat/generate` flow.

Sanity check (safe): enable `GET /api/diag` by setting the Edge Function secret `WEAFRICA_DEBUG_DIAG_TOKEN`, then run:

- `curl -sS -H "x-debug-token: $DEBUG_TOKEN" "$BASE_URL/api/diag" | python3 -m json.tool`

It should show `has_service_role_key=true` and `has_firebase_project_id=true`.

If you see `401 Invalid Firebase ID token` (e.g. on `/api/agora/token`), set the Edge Function secrets and redeploy:

- `supabase secrets set FIREBASE_PROJECT_ID=weafrica-music-85cdc`
- `supabase secrets set WEAFRICA_DEBUG_DIAG_TOKEN="..."` (recommended)
- `supabase functions deploy api --no-verify-jwt`

## Getting Started

## Android Size For Play Store

To generate a smaller Android artifact for Google Play, build an AAB (not APK) with symbol splitting:

- `bash tool/build_android_play_small.sh`

If you need a much faster build first (for quick validation/internal upload):

- `bash tool/build_android_play_fast.sh`

Then run the small optimized build before final rollout to production.

This produces:

- `build/app/outputs/bundle/release/app-release.aab`
- `build/symbols/android` (keep this for crash symbolication)

Notes:

- The Android config is set to ARM ABIs only (`armeabi-v7a`, `arm64-v8a`) to reduce native size.
- Upload the `.aab` to Play Console; Google Play delivers optimized splits per device.
- If size is still high, consider disabling optional heavy native features (for example Agora extension libs) per release profile.

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# musicweb.weafrica.net
