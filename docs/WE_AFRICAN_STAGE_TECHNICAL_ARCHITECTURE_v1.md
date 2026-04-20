# 🎭 WE AFRICAN STAGE — Technical Architecture (v1)

**Document Status:** Draft → Developer-ready v1  
**Classification:** Technical Architecture · No Code  
**Date:** February 27, 2026

**Companion docs**
- Product spec: `docs/WE_AFRICAN_STAGE_PLATFORM_SPEC_v1.md`
- Push notifications architecture: `docs/PUSH_NOTIFICATION_ARCHITECTURE.md`

---

## 1) Scope
This document translates the product spec into implementable technical decisions for:
- Identity & auth
- Data model (Postgres/Supabase)
- Realtime contracts (Agora + Supabase Realtime)
- API surface (Edge Function endpoints)
- Client architecture (Flutter patterns)
- Ops: moderation, audit, fraud/risk, observability

**Out of scope (v1):** final UI visuals, animation assets, sound design, and detailed screen pixel specs.

---

## 2) Current Stack (Observed in this repo)

### Client
- Flutter app
- Routing: `go_router`
- State mgmt: `provider`

### Identity + Messaging
- Firebase Auth (Bearer Firebase ID token)
- Firebase Cloud Messaging (push notifications)

### Backend + DB
- Supabase Postgres for persistent data
- Supabase Edge Function: `supabase/functions/api/index.ts` serving `/api/*`
- Service-role Supabase client inside Edge Function (bypasses RLS when needed)

### Realtime
- Agora RTC: live audio/video
- Agora RTM: ephemeral chat/gift events (token minted by backend)
- Supabase Realtime (WebSockets): authoritative score/session status broadcast from DB changes

---

## 3) Design Principles (Non-negotiable)
- **Server authoritative scoring:** clients render; server finalizes.
- **Idempotent gift spending:** retries must not double-charge.
- **Firebase UID is the primary user identity across systems** (Edge Function already uses this).
- **Feature gating enforced twice:** UI gates for UX + API gates for security.
- **Battle lifecycle is a state machine** (no ad-hoc transitions).

---

## 4) Identity, Roles, Tiers

### 4.1 Identity source of truth
- Firebase Auth is the identity provider.
- Every authenticated API call sends `Authorization: Bearer <Firebase ID token>`.
- Backend validates token with Firebase Project ID and issuer.

### 4.2 Roles vs tiers
- **Roles**: capabilities (viewer/dj/artist/radio_host/moderator/admin). Multi-role allowed.
- **Tier**: economic + visibility privileges for creators (rising/verified/elite).

### 4.3 Recommended persistence model
Because the repo already uses `creator_profiles` and `profiles`, standardize to:
- `profiles` (one row per Firebase UID): base public identity, role set, status
- `creator_profiles` (one row per creator): creator-facing identity and creator tier

**Additions required for Stage**
- Expand `creator_profiles.role` beyond `artist|dj` to include `radio_host` (and allow multi-role via separate table or array).
- Add tier fields: `tier`, `verification_state`, `payout_split_basis_points`.

### 4.4 Verification state machine (storage)
Persist verification as a state machine:
- `not_creator → applied → tutorial_pending → rising_active → verified_pending_review → verified_active → elite_active → (rejected|suspended)`

Store:
- `verification_state`
- timestamps for key transitions
- `verification_artifacts` references (document IDs, file paths)

---

## 5) Data Storage: Supabase Postgres

### 5.1 Identity tables (baseline)
- `profiles` (already used in Edge Function provisioning)
- `creator_profiles` (exists in `tool/supabase_schema.sql`)

### 5.2 Stage domain tables (proposed)
Names below are optimized for:
- clear joins
- realtime feeds via Supabase Realtime
- atomic RPC functions

**Sessions**
- `stage_sessions`
  - `id (uuid)`
  - `mode` (`dj_battle|artist|concert|radio`)
  - `status` (`scheduled|lobby|countdown|live|ended|finalized|cancelled`)
  - `channel_id` (Agora channel)
  - `host_a_uid`, `host_b_uid` (nullable for non-battle modes)
  - `started_at`, `ends_at`, `ended_at`, `finalized_at`
  - `config` (jsonb snapshot)

**Battle scoreboard (authoritative)**
- `stage_battle_state`
  - `session_id (uuid, pk/fk)`
  - `score_a`, `score_b`
  - `gifts_total_a`, `gifts_total_b`
  - `winner_uid`, `is_draw`
  - `top_gifters` (jsonb)
  - `updated_at`

**Gift catalog**
- reuse existing `live_gifts` table pattern (already referenced by `/api/live/gifts`).

**Gift events ledger (immutable)**
- `stage_gift_events`
  - `id (uuid)`
  - `session_id`
  - `channel_id`
  - `from_uid`
  - `to_side (A|B)` and/or `to_uid`
  - `gift_id`
  - `coin_cost`
  - `created_at`
  - `idempotency_key` (unique per `from_uid` + `idempotency_key`)

**Wallet / balances**
- reuse existing wallet tables and patterns if present (`wallets`, `artist_wallets`, coin ledger tables).
- recommended: maintain an **append-only ledger** + computed balances.

### 5.3 RLS strategy (recommended)
- Use RLS for client direct reads where safe (discovery feeds).
- Keep mutation flows (spend coins, start session, finalize) behind Edge Function + RPCs.

---

## 6) Realtime Architecture

### 6.1 Channels & responsibilities
- **Agora RTC:** audio/video transport only.
- **Agora RTM:** ephemeral UX events (chat messages, “gift animation” triggers).
- **Supabase Realtime:** authoritative state replication (session status, scoreboard, viewer count snapshots).

### 6.2 Authoritative update path
1) Viewer sends gift via API (`/api/live/send_gift` for current repo; Stage can extend it).
2) Backend calls atomic RPC:
   - deduct coins
   - insert gift event
   - update scoreboard
3) DB row changes broadcast to watchers via Supabase Realtime (score/totals)
4) Optionally: sender also emits RTM message for animation immediacy.

### 6.3 Latency targets mapping
- Gifts animation: RTM (<200ms)
- Score updates: Supabase Realtime (<100–500ms typical, depends on network)
- Comments: RTM (<500ms)
- Viewer count: periodic update (<2s)

---

## 7) Agora Conventions

### 7.1 Channel naming
Align with Edge Function validation (already enforced):
- Normal lives: `live_<uuid>` or legacy `weafrica_live_<uuid>`
- Battles: `weafrica_battle_<battle_id>`

### 7.2 Token minting endpoints (already in repo)
- `POST /api/agora/token` (RTC)
  - body: `{ channel_id, role: broadcaster|audience, ttl_seconds?, uid? }`
  - rule: battle broadcasters require Firebase auth
- `POST /api/agora/rtm/token` (RTM)
  - Firebase auth required (or test access in debug)

### 7.3 UID strategy
- RTC `uid` is numeric (Agora requirement). Use:
  - stable hash of Firebase UID → 32-bit int, OR
  - server-allocated uid per session host claim

**Constraint:** battle host claiming is limited to max 2 broadcasters (already enforced via `battle_claim_host`).

---

## 8) API Surface (Edge Function)

### 8.1 Existing endpoints already relevant
These exist today and can be used as Stage building blocks:
- `GET /api/diag` (debug health)
- `POST /api/agora/token`
- `POST /api/agora/rtm/token`
- Battle lifecycle:
  - `GET /api/battle/status?battle_id=...`
  - `POST /api/battle/ready`
  - `POST /api/battle/start`
  - `POST /api/battle/end`
  - invites + quick match endpoints
- Live sessions presence:
  - `POST /api/live/sessions/start`
  - `POST /api/live/sessions/heartbeat`
  - `POST /api/live/sessions/end`
- Gift catalog + spend:
  - `GET /api/live/gifts`
  - `POST /api/live/send_gift`
- Push:
  - `POST /api/push/register`
- Role/profile provisioning:
  - `POST /api/auth/provision-profile`
  - `POST /api/auth/provision-creator`
  - `GET /api/auth/role`

### 8.2 Stage-specific endpoints (proposed)
Use these to implement the product spec without overloading “battle” endpoints:

**Creator onboarding (Rising)**
- `GET /api/creator/eligibility`
  - returns: follower_count, phone_verified, tutorial_complete, eligible
- `POST /api/creator/tutorial/complete`
- `POST /api/creator/apply`
  - transitions `not_creator → applied → tutorial_pending` (or immediate)

**Tiers**
- `POST /api/creator/verified/submit`
- `POST /api/admin/creator/verified/approve`
- `POST /api/admin/creator/verified/reject`
- `POST /api/admin/creator/elite/invite`

**Stage sessions (generic)**
- `POST /api/stage/sessions/create`
- `POST /api/stage/sessions/start_countdown`
- `POST /api/stage/sessions/start`
- `POST /api/stage/sessions/end`
- `GET /api/stage/sessions/live` (discovery feed)

**Gifts & scoring**
- `POST /api/stage/gifts/send` (alias/upgrade path from `/api/live/send_gift`)
- `GET /api/stage/sessions/:id/state`

**Moderation**
- `POST /api/moderation/report`
- `POST /api/moderation/action` (mute/remove/end)

---

## 9) Battle Lifecycle (State Machine)

Recommended states for battles:
- `lobby` (hosts connect, ready checks)
- `countdown` (T-5 ritual)
- `live` (gifts + scoring enabled)
- `ended` (no more gifts)
- `finalized` (payout distribution locked)

Rules:
- `start` requires both hosts ready.
- `end` is server-finalized when `ends_at` is reached (already supported via `battle_finalize_due`).

---

## 10) Gift Spending, Scoring, Payouts

### 10.1 Gift processing
- Clients must send an idempotency key per gift spend attempt.
- Backend must enforce:
  - rate limits (already does basic 3s per channel/user)
  - battle status must be `live`
  - time window not exceeded

### 10.2 Score computation
- Score = sum(gift coin_cost × multiplier)
- Multipliers are server-configured per gift tier.

### 10.3 Tier snapshot for audit
When generating earnings, store:
- creator tier at time of gift
- payout split used

This prevents retroactive tier changes from rewriting history.

---

## 11) Rankings Pipeline

### 11.1 Snapshot model
- Generate `ranking_snapshots` for:
  - weekly category leaderboards
  - monthly tournament seeds
  - continental/global views

### 11.2 Implementation options
- Use Postgres scheduled jobs (pg_cron) OR Edge Function scheduled triggers.
- Store snapshots as immutable rows for auditability.

---

## 12) Moderation & Safety (Implementation Model)

### 12.1 Pre-live
- gate “Enter Stage” if creator is suspended/unverified.
- require guidelines acknowledgement per season/version.

### 12.2 During live
- real-time actions:
  - mute chat (per session)
  - remove viewer
  - end session

Persist all actions:
- moderator uid
- reason
- timestamp
- evidence refs

### 12.3 Post-live
- strike system with thresholds (3 strikes)
- appeals workflow

---

## 13) Flutter Client Architecture (Recommended)

### 13.1 Folder placement
Follow existing repo conventions:
- `lib/features/stage/` for Stage UI + view models
- `lib/services/` for cross-feature services (Agora, gifts, stage session service)
- `lib/data/` for models + repositories

### 13.2 State management
- Keep `provider` as baseline:
  - `ChangeNotifier` per feature controller
  - repositories injected via Providers
  - network calls via a single API client (Edge Function base URL)

### 13.3 Network/auth
- All protected calls attach Firebase ID token
- Use Edge Function `/api/*` routes via a single `WeafricaApi` client

---

## 14) Observability & Diagnostics

- Use `/api/diag` for deployment validation (already exists).
- Log structured events for:
  - battle start/end/finalize
  - gift spend failures
  - token mint failures
  - moderation actions

---

## 15) Open Decisions (Confirm before Phase 1 coding)
1) Where does `follower_count` live (Supabase `profiles` vs separate social graph tables)?
2) Phone verification: Firebase Phone Auth only, or also verify SIM/country?
3) Tier rules engine: pure SQL constraints + RPCs, or Edge Function logic?
4) Comments persistence: RTM-only ephemeral vs also store in DB (for replays/moderation).
5) “Concert Mode” ticketing provider: PayChangu only or multiple gateways?

---

## 16) Quick Alignment Checklist
- Uses Firebase Auth everywhere for identity
- Keeps Supabase as persistent DB + Edge Functions API
- Uses Agora for streaming and RTM UX events
- Uses Supabase Realtime for authoritative score/session status
- Adds tiers + verification + expanded roles to existing profile model
