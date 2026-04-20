# WE AFRICAN STAGE — Build-Ready Spec v1.1

This document refines the v1 Stage architecture into **build-ready contracts**, aligned to what already exists in this repo (Flutter + Firebase Auth + Supabase Postgres + Supabase Edge Function `api` + Agora).

**What this adds vs v1:**
- Stage concept → **existing schema** mapping (and what’s missing)
- Explicit **API request/response payloads** (based on `supabase/functions/api/index.ts` + Flutter clients)
- Minimal **new tables** required (rankings snapshots)
- Concrete **migration plan**

---

## 0) Conventions (Authoritative)

### Identity
- **User ID everywhere is the Firebase UID**, stored as `text` in Postgres.
- Supabase Auth is **not** the identity source for app users.

### API auth
- Authenticated endpoints expect: `Authorization: Bearer <Firebase ID token>`.
- Some endpoints allow “test access” in debug environments (server-side), but production clients should assume Firebase is required unless noted.

### Channel ID rules (Agora + gifts)
The backend enforces allowed channel prefixes:
- Normal lives: `live_…` (or legacy `weafrica_live_…`)
- Battles: `weafrica_battle_<battle_id>`

These prefixes are validated in:
- `POST /api/agora/token`
- `POST /api/live/send_gift`

---

## 1) Stage Concept → Existing DB Schema Mapping

### Profiles / roles / tiers
- **Profiles**: `public.profiles`
  - Used by `/api/auth/provision-profile`, `/api/auth/provision-creator`, `/api/auth/role`, `/api/profiles/search`.
  - Common fields used in API: `id, username, display_name, full_name, avatar_url, role`.
- **Subscriptions (consumer tiers)**:
  - `public.subscription_plans` (catalog: `free|premium|platinum`)
  - `public.user_subscriptions` (per-user plan state)

Stage mapping:
- Stage **Consumer Tier** = `user_subscriptions.plan_id` (joined to `subscription_plans`)
- Stage **Creator Role** = `profiles.role in ('artist','dj')`

### LIVE NOW (creator presence)
- **Live presence table (realtime)**: `public.live_sessions`
  - Key fields used today:
    - `channel_id` (string)
    - `host_id` (Firebase UID)
    - `artist_id` (Firebase UID; currently mirrors host)
    - `host_name`, `title`, `thumbnail_url`
    - `category` (`artist|battle`)
    - `viewer_count`
    - `is_live`, `started_at`, `last_heartbeat_at`, `ended_at`, `updated_at`

Stage mapping:
- Stage **Stage Session (Live)** = `live_sessions` row (source of truth for “LIVE NOW” cards)
- Stage **Discover feed** can query `live_sessions` (public select is allowed for live rows per RLS in migrations)

### Battles (1v1)
- **Battle state table**: `public.live_battles`
  - Lifecycle fields:
    - `battle_id` (text), `channel_id` (`weafrica_battle_<battle_id>`)
    - `status` (`waiting|live|ended`)
    - hosts: `host_a_id, host_b_id`
    - readiness: `host_a_ready, host_b_ready`
    - time: `started_at, ends_at, ended_at`
  - Results/payout fields (Step 6 migration):
    - `host_a_score, host_b_score`
    - `winner_uid, is_draw`
    - `total_spent_coins, platform_fee_coins, winner_payout_coins, loser_payout_coins`
    - `top_gifters` (jsonb)
  - Setup/metadata fields (Step 8 migration):
    - `title, category, duration_seconds, scheduled_at`
    - `access_mode ('free'|'subscribers'|'ticket')`, `price_coins`
    - `gift_enabled, voting_enabled`
    - `battle_format ('continuous'|'rounds')`, `round_count`

Stage mapping:
- Stage **Battle** = `live_battles` row
- Stage **Battle Live Card** = `live_sessions` row mirrored from battle start (best-effort), but **battle truth remains `live_battles`**
- Stage **Upcoming battles** = `live_battles.scheduled_at` (if set)

### Gifts + wallet economy
- **Viewer wallet**: `public.wallets (user_id, coin_balance, updated_at)`
- **Creator earnings wallet**: `public.artist_wallets (artist_id, earned_coins, withdrawable_coins, updated_at)`
- **Gift catalog**: `public.live_gifts (id, name, coin_cost, icon_name, sort_order, enabled)`
- **Gift events ledger**: `public.live_gift_events`
  - Common fields: `live_id, channel_id, from_user_id, sender_name, to_host_id, gift_id, coin_cost, created_at`
  - Battle support: optional `battle_id`
- **Coin topups**:
  - `public.coin_packages` (catalog)
  - `public.payments` (pending/completed reconciliation)
- **General finance ledger**: `public.transactions` (`type` includes `gift`, `battle_reward`, `coin_purchase`, etc.)

Stage mapping:
- Stage **Gift sent** = insert into `live_gift_events` + wallet debit (via RPC)
- Stage **Battle pot / payouts** = handled by `battle_send_gift` + `battle_finalize_due` (DB RPCs)

### Chat / comments / messages
- **Realtime chat (recommended)**: `public.live_messages`
  - Designed to be in a realtime publication; supports public read/write per migrations.
- **Legacy chat**: `public.live_chat_messages`

Stage mapping:
- Stage **Comments** = `live_messages`
- (Optional cleanup) Deprecate `live_chat_messages` once UI standardizes.

### Moderation / reports
- **Reports**: `public.live_reports`
  - Public insert allowed; public select denied.

Stage mapping:
- Stage **Report** = `live_reports` row
- Stage **Moderation queue** = admin-only read path (service role)

---

## 2) API Contracts (Request/Response Payloads)

All endpoints are under the Edge Function `api`.

### 2.1 Agora

#### POST `/api/agora/token`
Mint an Agora **RTC** token.

Request body:
```json
{
  "channel_id": "weafrica_battle_<battle_id>",
  "role": "broadcaster",
  "ttl_seconds": 3600,
  "uid": 12345
}
```
Notes:
- `channel_id` may also be sent as `channelName|channelId|channel`.
- `role` accepts: `broadcaster|audience` and also `publisher|subscriber`.
- Battle broadcaster tokens require Firebase auth.

Response:
```json
{
  "ok": true,
  "token": "<agora_rtc_token>",
  "expires_at": 1730000000,
  "token_version": "006",
  "app_id": "<agora_app_id>",
  "channel_id": "weafrica_battle_...",
  "uid": 12345,
  "role": "broadcaster",
  "agora_role": "publisher"
}
```

#### POST `/api/agora/rtm/token`
Mint an Agora **RTM** token.

Request body:
```json
{ "ttl_seconds": 3600 }
```
Response:
```json
{
  "ok": true,
  "token": "<agora_rtm_token>",
  "expires_at": 1730000000,
  "token_version": "006",
  "app_id": "<agora_app_id>",
  "user_id": "<firebase_uid>"
}
```

### 2.2 Live sessions (presence)

#### POST `/api/live/sessions/start`
Marks a channel live (and optionally broadcasts push to subscribers).

Request body:
```json
{
  "channel_id": "live_<creator_uid>",
  "host_name": "DJ Name",
  "title": "Friday Night Set",
  "category": "artist",
  "thumbnail_url": "https://..."
}
```
Response:
```json
{ "ok": true, "live": true, "already_live": false }
```

#### POST `/api/live/sessions/heartbeat`
Request body:
```json
{ "channel_id": "live_<creator_uid>" }
```
Response:
```json
{ "ok": true, "heartbeat": true }
```

#### POST `/api/live/sessions/end`
Request body:
```json
{ "channel_id": "live_<creator_uid>" }
```
Response:
```json
{ "ok": true, "live": false }
```

### 2.3 Gifts

#### GET `/api/live/gifts`
Response:
```json
{
  "ok": true,
  "gifts": [
    { "id": "rose", "name": "Rose", "coin_cost": 10, "icon_name": "rose", "sort_order": 1, "enabled": true }
  ]
}
```

#### POST `/api/live/send_gift`
Request body:
```json
{
  "live_id": "<uuid>",
  "channel_id": "live_<creator_uid>",
  "to_host_id": "<creator_uid>",
  "gift_id": "rose",
  "sender_name": "Alice"
}
```
Response:
```json
{
  "ok": true,
  "new_balance": 120,
  "event_id": "<uuid>",
  "coin_cost": 10,
  "gift_id": "rose"
}
```
Notes:
- Rate-limited per-user/channel (currently ~1 gift / 3s).
- If `channel_id` is a battle channel (`weafrica_battle_...`), gifts go into the battle pot.

### 2.4 Battle lifecycle

#### GET `/api/battle/status?battle_id=<battle_id>`
Public read.

Response:
```json
{ "ok": true, "battle": { "battle_id": "...", "channel_id": "weafrica_battle_...", "status": "waiting" } }
```
(Full object includes host IDs, ready flags, time fields, and result/payout fields once ended.)

#### POST `/api/battle/ready`
Request body:
```json
{ "battle_id": "<battle_id>", "ready": true }
```
Response:
```json
{ "ok": true, "battle": { "battle_id": "...", "host_a_ready": true, "host_b_ready": false } }
```

#### POST `/api/battle/start`
Request body:
```json
{ "battle_id": "<battle_id>", "duration_seconds": 1200 }
```
Response:
```json
{ "ok": true, "battle": { "battle_id": "...", "status": "live", "ends_at": "2026-..." } }
```
Notes:
- Mirrors a `live_sessions` row for discoverability (best-effort).
- Broadcasts a push “LIVE BATTLE” to subscribers (best-effort).

#### POST `/api/battle/end`
Request body:
```json
{ "battle_id": "<battle_id>", "reason": "host_left" }
```
Response:
```json
{ "ok": true, "battle": { "battle_id": "...", "status": "ended" } }
```

### 2.5 Battle invites + quick match

#### GET `/api/battle/invites?box=inbox|outbox|all&status=pending|accepted|declined|expired|all&limit=50`
Response:
```json
{
  "ok": true,
  "invites": [
    {
      "id": "<uuid>",
      "battle_id": "<battle_id>",
      "from_uid": "<uid>",
      "to_uid": "<uid>",
      "status": "pending",
      "created_at": "2026-...",
      "expires_at": "2026-...",
      "responded_at": null,
      "from_profile": { "id": "...", "username": "...", "display_name": "...", "avatar_url": "...", "role": "dj" },
      "to_profile": { "id": "...", "username": "...", "display_name": "...", "avatar_url": "...", "role": "dj" }
    }
  ]
}
```

#### POST `/api/battle/invite/create`
Request body:
```json
{
  "to_uid": "<recipient_uid>",
  "ttl_seconds": 60,
  "battle": {
    "title": "Afro House Clash",
    "category": "house",
    "duration_seconds": 1800,
    "scheduled_at": "2026-02-27T20:00:00Z",
    "access_mode": "free",
    "price_coins": 0,
    "gift_enabled": true,
    "voting_enabled": false,
    "battle_format": "continuous",
    "round_count": 3
  }
}
```
Response:
```json
{
  "ok": true,
  "invite": {
    "invite_id": "<uuid>",
    "battle_id": "<battle_id>",
    "channel_id": "weafrica_battle_<battle_id>",
    "expires_at": "2026-..."
  }
}
```
Notes:
- Anti-spam protections:
  - blocks duplicate pending invites
  - caps active pending outbox invites
- Best-effort: stores `battle` metadata into `live_battles` if Step 8 migration is applied.

#### POST `/api/battle/invite/respond`
Request body:
```json
{ "invite_id": "<uuid>", "action": "accept" }
```
Response:
```json
{ "ok": true, "battle": { "battle_id": "..." }, "action": "accept" }
```

#### POST `/api/battle/quick_match/join`
Request body:
```json
{ "role": "dj", "country": "MW" }
```
Response (queued):
```json
{ "ok": true, "queued": true }
```
Response (matched immediately):
```json
{ "ok": true, "matched": true, "battle": { "battle_id": "...", "channel_id": "weafrica_battle_..." } }
```

#### GET `/api/battle/quick_match/poll`
Response:
```json
{ "ok": true, "matched": false }
```
(or `matched: true` with a `battle` object)

#### POST `/api/battle/quick_match/cancel`
Response:
```json
{ "ok": true, "canceled": true }
```

### 2.6 Wallet + coin topups

#### GET `/api/wallet/me`
Response:
```json
{ "ok": true, "user_id": "<uid>", "coin_balance": 0, "updated_at": "2026-..." }
```

#### GET `/api/artist_wallet/me`
Response:
```json
{ "ok": true, "artist_id": "<uid>", "earned_coins": 0, "withdrawable_coins": 0, "updated_at": "2026-..." }
```

#### GET `/api/coins/packages`
Response:
```json
{ "ok": true, "packages": [ { "id": "...", "title": "...", "coins": 100, "bonus_coins": 0, "price": 1000, "currency": "MWK", "sort_order": 1 } ] }
```

#### POST `/api/coins/paychangu/start`
Request body:
```json
{ "package_id": "<package_id>", "country_code": "MW", "user_id": "<optional_uid>" }
```
Response:
```json
{
  "ok": true,
  "checkout_url": "https://...",
  "provider_reference": "<tx_ref>",
  "tx_ref": "<tx_ref>",
  "package_id": "<package_id>",
  "user_id": "<uid>"
}
```

### 2.7 Push notifications (device + LIVE NOW)

#### POST `/api/push/register`
Registers an FCM token for a user (best-effort upsert across schema variants).

Request body:
```json
{
  "token": "<fcm_token>",
  "platform": "android",
  "topics": ["live_now"],
  "country_code": "mw",
  "device_model": "Pixel 8",
  "app_version": "1.0.0",
  "locale": "en"
}
```

Response (success):
```json
{ "ok": true, "success": true, "message": "Device token registered", "data": { "id": 123 } }
```

Response (best-effort failure; still 200-level JSON in some schema-mismatch cases):
```json
{ "ok": false, "success": false, "error": "supabase_error", "message": "..." }
```

#### POST `/api/live/notify/subscribe`
Subscribes the current user to LIVE NOW push broadcasts.

Request body:
```json
{}
```

Response:
```json
{ "ok": true, "subscribed": true }
```

### 2.8 Stage rankings (leaderboards)

#### GET `/api/stage/rankings?ranking_type=...&scope=...&scope_key=...&period_end=...`
Returns the latest (or a specific period) leaderboard snapshot from `stage_rankings_snapshots`.

Query params:
- `ranking_type` (required): `coins_earned|gifts_received|battle_wins|followers_growth|view_minutes`
- `scope` (optional): `global|country|city|genre` (default `global`)
- `scope_key` (optional): scope value (e.g. `MW`, `Lilongwe`, `afrohouse`)
- `period_end` (optional): ISO timestamp; when provided, fetches that specific period’s snapshot

Response:
```json
{
  "ok": true,
  "snapshot": {
    "id": "<uuid>",
    "ranking_type": "coins_earned",
    "scope": "global",
    "scope_key": null,
    "period_start": "2026-02-20T00:00:00.000Z",
    "period_end": "2026-02-27T00:00:00.000Z",
    "computed_at": "2026-02-27T00:10:00.000Z",
    "entries": [
      { "user_id": "<uid>", "rank": 1, "score": 12345, "meta": { "display_name": "..." } }
    ],
    "meta": {}
  }
}
```

#### GET `/api/rankings/weekly?ranking_type=...&scope=...&scope_key=...`
Convenience endpoint that tries to return the **last completed UTC week** snapshot.

Response:
```json
{
  "ok": true,
  "period": "weekly",
  "period_start": "2026-02-17T00:00:00.000Z",
  "period_end": "2026-02-24T00:00:00.000Z",
  "snapshot": null
}
```

#### GET `/api/rankings/monthly?ranking_type=...&scope=...&scope_key=...`
Convenience endpoint that tries to return the **last completed UTC month** snapshot.

Response:
```json
{
  "ok": true,
  "period": "monthly",
  "period_start": "2026-01-01T00:00:00.000Z",
  "period_end": "2026-02-01T00:00:00.000Z",
  "snapshot": null
}
```

#### GET `/api/rankings/continental?ranking_type=...`
Convenience endpoint that currently maps to **global scope** (continent filtering is not modeled in DB yet).

Response:
```json
{
  "ok": true,
  "period": "continental",
  "period_start": null,
  "period_end": null,
  "snapshot": null
}
```

### 2.9 Utility: profile search

#### GET `/api/profiles/search?q=<query>&limit=10`
Response:
```json
{ "ok": true, "profiles": [ { "id": "...", "username": "...", "display_name": "...", "avatar_url": "...", "role": "dj" } ] }
```

---

## 3) New Tables Required for Stage v1.1 (Rankings)

Rankings are the clearest missing primitive: the repo has battle results/payouts, but no durable “leaderboard snapshots” table.

### 3.1 `public.stage_rankings_snapshots` (minimal, flexible)
Recommended shape (store the leaderboard as a JSON array; recompute periodically via a scheduled job/Edge Function):

```sql
create table if not exists public.stage_rankings_snapshots (
  id uuid primary key default gen_random_uuid(),
  ranking_type text not null check (ranking_type in (
    'coins_earned',
    'gifts_received',
    'battle_wins',
    'followers_growth',
    'view_minutes'
  )),
  scope text not null default 'global' check (scope in ('global','country','city','genre')),
  scope_key text,
  period_start timestamptz not null,
  period_end timestamptz not null,
  computed_at timestamptz not null default now(),
  entries jsonb not null, -- [{ user_id, rank, score, meta? }, ...]
  meta jsonb not null default '{}'::jsonb
);

create unique index if not exists stage_rankings_snapshots_unique
  on public.stage_rankings_snapshots (ranking_type, scope, scope_key, period_start, period_end);

create index if not exists stage_rankings_snapshots_period_idx
  on public.stage_rankings_snapshots (period_end desc, computed_at desc);
```

RLS recommendation:
- Allow `select` for `anon, authenticated` (leaderboards are public)
- Deny `insert/update/delete` except service role (computed server-side)

---

## 4) Migration Plan (Concrete)

### Step A — Confirm baseline migrations are applied
Ensure the following already-landed tables/migrations are deployed:
- Live presence: `live_sessions` (+ premium fields `category, viewer_count`)
- Battle lifecycle: `live_battles` + matching/invites tables + RPCs
- Battle metadata: `20260226000100_battles_step8_setup_metadata.sql`
- Wallet + gifts: `wallets`, `live_gifts`, `live_gift_events`, and RPCs `send_gift`, `battle_send_gift`
- Moderation: `live_reports`

### Step B — Add rankings snapshot migration
Add a new migration (next timestamp) creating `stage_rankings_snapshots` + indexes + RLS.

### Step C — Add a rankings read endpoint (optional but recommended)
Implement a read-only Edge route (e.g. `GET /api/stage/rankings?...`) that returns the latest snapshot for a given type/scope.
- This keeps leaderboard reads consistent across clients and avoids direct SQL from the app.

---

## 5) Open Decisions (Keep v1.1 Small)

- **Chat table standardization**: confirm `live_messages` is the single source of truth (and stop writing `live_chat_messages`).
- **Ranking computation**: scheduled cadence (hourly/daily) and which sources define “Rising” (followers vs coins vs watch-time).
- **Access control**: whether `stage_rankings_snapshots` is fully public or requires auth.
