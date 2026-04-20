# Realtime at Scale (10K Concurrent in One Live Room)

Assumptions (locked):

- 10K concurrent users in **one** live room
- Hardest correctness stream: **gifts + battle score**
- We do **layered realtime**, not “realtime everything”

## Layered Realtime Contract

- **CRITICAL (instant):** Gifts, Battle score deltas
- **IMPORTANT (near realtime):** Chat
- **SOFT (eventual):** Viewer count
- **OFFLINE:** Analytics

## Core Principle

Separate **truth** from **fanout**.

```
DB truth  ->  fanout bus  ->  realtime transport  -> UI
```

### Concrete mapping in this repo

- **Truth (money + audit):** `public.live_gift_events` + wallet ledger (`public.wallets`, `public.wallet_transactions`)
- **Truth (battle state):** `public.live_battles`
- **Fanout bus (UI events):** `public.live_messages` (kind=`gift`/`message`/`system`)
- **Realtime transport:** Supabase Realtime streaming `live_messages` (and low-frequency session rows)
- **UI:** Flutter

Important: `live_messages` is **not** financial truth. It is a small, replay-light fanout surface.

## Gifts (Critical)

### What breaks at 10K

- Having every client poll/read `live_gift_events`
- Using `live_gift_events` as the realtime stream (it is truth + high write volume)

### Production flow

1) Viewer sends gift intent
2) Edge validates + calls atomic DB RPC (`send_gift` / `battle_send_gift`)
3) DB writes:
   - Deducts wallet balance
   - Inserts `live_gift_events` (truth)
4) Edge emits **one lightweight** fanout event into `live_messages` (kind=`gift`, `dedupe_key=event_id`)
5) Clients subscribed to `live_messages` render the animation

#### Fanout payload

`live_messages.message` is a TEXT column. For `kind='gift'`, it should be a compact JSON string.

Recommended minimal keys:

- `type`: `"gift"`
- `event_id`: UUID (dedupe key)
- `gift_id`
- `coin_cost`
- `from_user_id`
- `sender_name`
- `to_host_id`
- `channel_id`
- `battle_id` (nullable)

## Battle Score (Critical, anti-lag)

### Correct model

- **Event deltas (fast):** each incoming gift fanout implies `+coin_cost` to `to_host_id`
- **Client local accumulate:** update displayed score immediately from deltas
- **Periodic resync (correctness):** every ~5–10 seconds, fetch authoritative score snapshot

### Authoritative snapshot source

Use `/api/battle/status` (Edge) which reads `live_battles.host_a_score/host_b_score`.

Requirement: the DB function `battle_send_gift` must increment these columns in the same transaction as the gift.
This avoids expensive “sum gifts” queries under load.

## Chat (Important, controlled realtime)

10K users can produce message explosions.

Minimum production controls:

- Server-side rate limit (e.g. 1 message / 2 seconds / user / live)
- Client renders only the last ~50–100 messages
- (Optional) VIP priority is a product decision, not a scaling requirement

Implementation direction in this repo:

- Prefer Edge-mediated inserts to `live_messages` for chat so you can enforce rate limits using Firebase identity.
- Avoid allowing anonymous/public inserts for production rooms.

## Viewer Count (Soft, eventual)

Do not update per join/leave.

Recommended model:

- Client heartbeat every 15–20 seconds
- Server aggregates active viewers and updates `live_sessions.viewer_count` periodically
- UI refreshes every few seconds

## Fanout Architecture

Goal: clients subscribe to **one** high-signal stream per live.

- Primary stream: `live_messages` filtered by `live_id`
- Secondary stream (low frequency): `live_sessions` filtered by `channel_id` for viewer count / status

Do not stream:

- Wallet rows
- Gift truth rows (`live_gift_events`) directly to clients
- Analytics tables

## Backpressure (must-have at 10K)

When the system is under load:

- Preserve: gift + score deltas
- Degrade: chat frequency / drop chat messages
- Avoid UI overload: queue animations and cap active animations (e.g. max 3–5)

If gift rate becomes too high for per-gift fanout, add **burst batching** at the fanout layer (aggregate multiple gifts into one UI event).

## Reconnect Strategy

On reconnect:

1) Fetch authoritative battle status (scores + timer)
2) Resume realtime subscription to `live_messages`
3) Optionally fetch last N seconds of `live_messages` for smooth UI continuity

No need to replay financial truth.
