# Admin ↔ Backend ↔ Consumer: Golden Rule + Feature Map + Test Playbook

Date: 2026-02-01

## 1) The Golden Rule (non‑negotiable)

Admin **NEVER** talks directly to the Consumer UI.

Admin and Consumer **only** talk to **one source of truth**:

- Backend APIs (Next.js routes / edge / server)
- Database (Supabase Postgres)

Required flow:

Admin Dashboard
→ (API / Supabase write)
Database
→ (API / Supabase read)
Consumer App

If something breaks, it is **always** in one of these 3 steps:

1. Admin → Database (WRITE)
2. Database → API (READ)
3. Consumer → API (DISPLAY)

Rule of thumb: **Stop** at the first failing step.

---

## 2) Feature Map (must exist or consumer will fail)

If an admin feature doesn’t appear in this map, it will **not reliably appear** in the consumer app.

Legend:
- **Admin Screen**: where ops/admin triggers the action
- **Admin API**: endpoint used by admin to write/read
- **DB Table(s)**: source of truth
- **Consumer API**: endpoint consumer reads (or should read)
- **Consumer Screen**: where it shows

> Notes:
> - “Consumer API” may be in a different repo. If it’s missing, treat it as a blocker.
> - Some modules in this admin repo are explicitly “stub/scaffolded”; those are marked.

| Admin Screen / Feature | Admin API (write/read) | DB Table(s) | Consumer API (read) | Consumer Screen |
|---|---|---|---|---|
| Subscription Promotions (create/archive) | `/api/admin/subscriptions/promotions` (GET/POST/PATCH) | `subscription_promotions` | `/api/subscriptions/promotions` (GET) | Promo banner / in-app announcements |
| Content Promotions (create/activate/deactivate) | `/api/admin/promotions` + `/api/admin/promotions/[id]` + `/api/admin/promotions/[id]/{activate|deactivate}` | `promotions` | `/api/promotions` (GET) | Promo banner / promo carousel |

| Ads Enabled by Country (toggle) | (server action in `/admin/ads`) | `countries.ads_enabled` | `/api/ads/config` (GET) | Ad display rules (show/hide ads) |

Notes:
- For backwards compatibility with older consumer builds, `/api/subscriptions/promotions` also includes active rows from `promotions` mapped into the same response shape.
| Subscription Plans (CRUD) | `/api/admin/subscriptions/plans` (GET/POST/PATCH/DELETE) | `subscription_plans` | **TBD** (must exist: e.g. `/api/subscriptions/plans`) | Paywall / plan picker |
| Subscription Content Access (rules) | `/api/admin/subscriptions/content-access` (GET/POST/PATCH) | `subscription_content_access` | **TBD** | Content gating (premium/free rules) |
| Push Notifications (compose/send) | `/api/admin/notifications/push` (GET/POST/PATCH) + `/api/push/send` | `notification_device_tokens`, `notification_push_send_log` (and any notification tables used by admin route) | **TBD** (push is delivered, inbox requires table+endpoint) | Push + Inbox (if implemented) |
| Device Token Registration | `/api/push/register` | `notification_device_tokens` | N/A | N/A |
| Moderation: reports → actions | `/api/admin/moderation/reports/[id]` | `reports`, `moderation_actions`, plus affected content tables (`songs`, `videos`, `live_streams`) | **TBD** (consumer reads content filtered by `approved/is_active/status`) | Home/Discover/Video feed/Live |
| Artists (update/approve/verify/block/delete) | `/api/admin/artists/[id]` | `artists` (and related: `songs`, `videos`, `live_streams`) | **TBD** (`/api/artists`, `/api/artists/:id`, etc.) | Artist profile |
| DJs (update/approve/verify/block/delete) | `/api/admin/djs/[id]` | `djs` (and related: `live_streams`) | **TBD** | DJ profile / Live |
| Users (status/blocks/tools) | `/api/admin/users/[uid]` | `users` (+ `artists`, `djs`, `live_streams`) | **TBD** | Account / restrictions |
| Live Streams (ops actions) | `/api/admin/live-streams/[id]` | `live_streams` | **TBD** | Live browse/watch |
| Analytics events ingestion | `/api/events/ingest` | `analytics_events` | N/A | N/A |
| Risk flags (save/update) | (admin pages write directly) + `/api/admin/analytics/report` exports | `risk_flags` | N/A | Admin only |
| Finance tools / payouts / withdrawals | `/api/admin/finance/*`, `/api/admin/approvals/[id]` | `withdrawals`, `transactions`, `earnings_freeze_state`, `earnings_freeze_events` | N/A | Admin only |
| Growth → Promotions → Campaigns (new UI) | **NONE (local drafts only)** | **NONE (not connected)** | N/A | N/A |
| Ads → Campaigns | server actions in `/admin/ads/campaigns` | `ad_campaigns` | `/api/ads/campaigns` (GET active approved rows) | Ads surfaces |

### Action item: fill the missing Consumer APIs
For any row with **TBD** under Consumer API, pick the canonical endpoint name and implement it (or confirm it already exists in the consumer/backend repo).

---

## 3) Validate Admin → Database (WRITE test)

Run this for each admin action.

Checklist:
- Trigger the action in admin
- Open Supabase Table Editor for the table(s)
- Confirm row created/updated
- Confirm timestamps changed (`updated_at`, `created_at`)
- Confirm status flags match what consumer expects (examples: `approved`, `is_active`, `status`, `published`)
- Confirm no unexpected side effects on related tables

Example:
- Admin approves a song → verify `songs.approved = true` (and/or `songs.status = 'approved'`, depending on your schema)

If it’s wrong here: **STOP**. Fix admin write or DB constraints first.

---

## 4) Validate Database → API (READ test)

Now confirm the backend reads data correctly.

Checklist:
- Test the endpoint in browser / Postman
- Use the **exact filters** the consumer will use
- Confirm:
  - Correct data
  - Correct order (sorting)
  - Correct pagination
  - No hidden admin-only fields
  - Stable response shape

Example shape:
```json
{ "ok": true, "data": [ /* ... */ ] }
```

If API is wrong: fix backend/query/filters. **Do not** patch consumer to compensate.

---

## 5) Lock API Contracts (CRITICAL)

Consumer must trust the API shape.

For every consumer endpoint, lock:
- Field names
- Data types
- Nested structures

Recommended:
- Create a shared types module used by:
  - API route implementation (server)
  - Admin UI (if it renders the same payload)
  - Consumer app (ideally in a shared package or copied verbatim)

Minimal example contract:
```ts
export type SongPublic = {
  id: string
  title: string
  artist_name: string
  cover_url: string
  audio_url: string
  status: 'pending' | 'approved' | 'rejected'
}
```

Never silently rename fields or change meanings. If you must evolve, add a new versioned endpoint.

---

## 6) Consumer App: Read-only, no business logic

Consumer should:
- NOT guess status
- NOT re-implement admin filters
- NOT assume defaults

Consumer logic:
- If `response.ok` → render
- Else → empty state

The admin decides what exists; consumer displays it.

---

## 7) Real-time sync (optional, powerful)

Use Supabase realtime for:
- approvals
- promo banners
- live updates

Pattern:
- subscribe to table changes
- refetch the canonical consumer endpoint

---

## 8) Error + Empty states

For every consumer screen:
- Loading → shimmer
- Error → retry
- Empty → “Coming soon” / “No items yet”

This prevents “blank app” panic.

---

## 9) One-button end-to-end test (before every release)

1. Add/update content in admin
2. Refresh consumer
3. Confirm it appears
4. Update content in admin
5. Confirm consumer updates
6. (If deletion exists) delete/hide content
7. Confirm consumer hides it

Only when all pass: production-ready.

---

## 10) Current repo reality (important)

- This admin repo already has strong Supabase connectivity.
- Some modules are still scaffolded/stubs.
- Growth → Promotions → Campaigns still stores drafts locally, so it **cannot** power consumer until its own DB table + API are added.
- Ads → Campaigns is now wired to `ad_campaigns` with a consumer read endpoint at `/api/ads/campaigns`; only approved, enabled, in-window rows are returned.
