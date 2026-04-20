# AI Testing — Artist Studio + DJ Studio

This repo has 3 main “AI” surfaces to validate:

1) **Artist Studio (Beat MP3 generator)**
2) **DJ Studio (DJ battle “next track” decision AI)**
3) **Creator AI Dashboard** (DJ + Artist insights/advice)

This doc focuses on repeatable smoke tests that validate the full chain:
- client UI → Edge Function → DB rows → Storage signed URL (for MP3)

## Prereqs (backend)

- DB migrations applied (includes monetization + beat audio jobs):
  - supabase/migrations/20260207010000_ai_monetization_engine.sql
  - supabase/migrations/20260208060000_ai_beat_audio_jobs.sql
- Edge Function deployed:
  - supabase/functions/api/index.ts
- Secrets configured for the Edge Function:
  - `FIREBASE_PROJECT_ID`
  - `SUPABASE_SERVICE_ROLE_KEY`

### Beat MP3 generation (Replicate)

To test the paid MP3 flow, you must also set:
- `REPLICATE_API_TOKEN` (required)
- `WEAFRICA_AI_BEATS_BUCKET` (default: `ai_beats`)
- Optional: `WEAFRICA_REPLICATE_MUSIC_MODEL`, `WEAFRICA_REPLICATE_MUSIC_VERSION`

## Quick backend smoke test (recommended)

Run the existing script (now includes Creator Dashboard + Beat MP3 job polling):

- `BASE_URL="https://<ref>.functions.supabase.co" ID_TOKEN="<firebase id token>" ./tool/ai_monetization/smoke_test.sh`

Notes:
- `ID_TOKEN` is required for:
  - `GET /api/ai/balance`
  - `GET /api/dashboard/dj`
  - `GET /api/dashboard/artist`
  - `POST /api/beat/audio/start`
  - `GET /api/beat/audio/status`
- `TEST_TOKEN` (dev-only) can be used for some endpoints **only if** `WEAFRICA_ENABLE_TEST_ROUTES=true`.

## In-app testing (Artist Studio)

### Beat MP3 Generator

Entry point:
- Settings → **Beat MP3 Generator**

Expected behavior:
- When signed out → shows “Not signed in” on Generate.
- When signed in:
  1. Tap **Generate MP3**.
  2. UI shows Job ID + status changes.
  3. When `succeeded`, playback starts automatically.
  4. If balance is insufficient, you see a `payment_required` message with cost + balances.

Backend expectations:
- `POST /api/beat/audio/start` creates a row in `public.ai_beat_audio_jobs`.
- `GET /api/beat/audio/status` eventually returns `job.status=succeeded` and a `job.audio_url` (signed URL).
- Storage writes to bucket `ai_beats` at `{uid}/{jobId}.mp3` or `.wav`.

## In-app testing (DJ Studio)

### Creator AI Dashboard (DJ mode)

Entry point:
- Settings → **Creator AI Dashboard** → select **DJ**

Expected behavior:
- Tabs load:
  - Overview shows counts and averages.
  - Advice shows non-empty coaching items.
  - History shows recent events when present.

To generate real DJ history:
- Hit the endpoint `POST /api/dj/next` during a battle or via the smoke test.

### DJ “Next track” decision API (service-level)

The Edge Function implements:
- `POST /api/dj/next`

Expected behavior:
- Returns `{ decision, next_song_id, reasons[] }`
- When `coins_per_min` is high enough, response includes `crowd_boost_detected=true` and a message.

## In-app testing (DJ Live Battle)

This validates the “go live” battle flow end-to-end:
matchmaking/invite → battle row updates → ready/start/end → Agora join.

### Prereqs (backend)

- Migrations applied (minimum set for battles):
  - supabase/migrations/20260207000100_live_step2_1_battles.sql
  - supabase/migrations/20260207000200_live_step2_1_battle_agora_uid.sql
  - supabase/migrations/20260207001000_live_step4_ready_countdown.sql
  - supabase/migrations/20260208000200_live_step7_matching_invites.sql
  - (Recommended for scoring/payouts) supabase/migrations/20260208000100_live_step6_battle_results_payouts.sql
- Edge Function deployed:
  - supabase/functions/api/index.ts
- Edge Function secrets configured:
  - FIREBASE_PROJECT_ID
  - SUPABASE_SERVICE_ROLE_KEY
  - AGORA_APP_ID
  - AGORA_APP_CERTIFICATE

### Prereqs (app)

- Enable battles UI:
  - run/build with `--dart-define=WEAFRICA_FEATURE_BATTLES=true`
- Ensure the app can reach your Edge Function base URL:
  - either Supabase is configured (auto-derives `https://<ref>.functions.supabase.co`),
  - or set `--dart-define=WEAFRICA_API_BASE_URL=https://<ref>.functions.supabase.co`.

### Quick manual test (two DJ accounts)

On Device A (DJ A) and Device B (DJ B):

1. Sign in to Firebase (two different accounts).
2. Open Creator Dashboard as DJ.
3. Tap FIND A BATTLE on both devices.
4. Expected: a match is found and both navigate into the Live battle screen.
5. In the battle screen:
   - both hosts can join as broadcasters (no “Battle already has 2 hosts”).
   - set Ready for both sides.
   - start the battle; status becomes live and timer counts down.
   - each side can see the other’s video (or at least remote-joined state).
6. End the battle and verify it transitions to ended/finalized.

If you only want to validate backend state changes (no Agora), run the smoke test script:

- `BASE_URL="https://<ref>.functions.supabase.co" ID_TOKEN_A="..." ID_TOKEN_B="..." ROLE="dj" ./tool/live_battle/smoke_test.sh`

## Troubleshooting

- `/api/beat/audio/start` returns `503 not_configured`:
  - Set `REPLICATE_API_TOKEN` and redeploy the Edge Function.

- Beat MP3 job never reaches `succeeded`:
  - Check Replicate prediction status + limits.
  - Confirm Storage bucket exists (`ai_beats`) and service role can upload.

- Creator Dashboard returns empty:
  - DJ dashboard depends on rows in `dj_ai_events`.
  - Artist dashboard depends on `artist_wallets` and `live_gift_events`.
