# WeAfrica Music — Notification Center (Repo → Target Roadmap)

This document maps the **current repo state** to a **full in-app Notification Center**, with the **exact Supabase tables/functions** and **Flutter files** to touch.

## Current State (Verified in Repo)

### What users see today

- **Consumer bell → Notifications page** currently displays **announcements** (not per-user notifications).
  - UI: `lib/features/notifications/notifications_screen.dart`
  - Data source: `public.announcements` via `AnnouncementsStore`
  - Store: `lib/features/notifications/services/announcements_store.dart`
  - Navigation entry: bell icon in `lib/features/shell/app_shell.dart`

- **Creator dashboards already query `public.notifications`** (per-user-style rows with `title`, `body`, `created_at`, and optionally `read`).
  - Repository: `lib/features/artist/dashboard/repositories/artist_notification_repository.dart`
  - Model: `lib/features/artist/dashboard/models/dashboard_notification.dart`
  - Service: `lib/features/artist/dashboard/services/dashboard_notification_service.dart`

### Supabase SQL sources in this repo

There are **multiple** notification-related schema files under `tool/`:

- `tool/notifications_schema.sql`
  - Creates `public.notifications` as **per-user** records (`user_id`, `title`, `body`, `type`, `data`, `read`, `read_at`, etc)
  - Defines helper RPC: `public.get_unread_count(user_uuid uuid)`

- `tool/notification_analytics_schema.sql`
  - Creates analytics table `public.notification_logs` and stats views

- `tool/push_notification_schema.sql`
  - Creates `public.notification_device_tokens` (used by Flutter FCM registration)
  - Also creates a **different** `public.notifications` (campaign/template model), which **conflicts** with `tool/notifications_schema.sql`

**Important:** before applying any SQL, decide which `public.notifications` definition you want. The Flutter creator dashboard code strongly aligns with the **per-user** `tool/notifications_schema.sql` shape.

---

## Target State (Full Notification Center)

### UX / Behavior

- Bell badge shows **unread per-user notifications** (not “announcement count”).
- Notifications list:
  - unread first (or visually distinct)
  - tap item marks it read + navigates via `type` and/or `data`
  - pull-to-refresh
  - optional “mark all read”
- Push notifications are **persisted** (insert row into `public.notifications`) so the center works even if the push is missed.

### Target Data Model (Recommended for this repo)

Use `public.notifications` as the **per-user inbox**, matching `tool/notifications_schema.sql`:

- `id uuid`
- `user_id uuid`
- `title text`
- `body text`
- `type text` (e.g., `live_battle`, `comment_update`)
- `data jsonb` (deep link / entity ids)
- `read boolean`
- `read_at timestamptz`
- `created_at timestamptz`

Use `public.notification_device_tokens` for FCM tokens (FCMService already upserts here).

Use analytics logs (`public.notification_logs`) for delivery/open metrics (optional but already present in code).

---

## Repo-to-Target Developer Map (What to Touch)

### A) Supabase (tables/RLS/RPC)

**Tables to exist and be consistent**

- `public.notifications` (per-user inbox)
  - Source: `tool/notifications_schema.sql`
  - Must support `select` + `update` by the owning user (RLS)

- `public.notification_device_tokens` (token registry)
  - Source: `tool/push_notification_schema.sql` (extract table if you are using per-user `notifications`)

- Optional analytics:
  - `public.notification_logs` and views
  - Source: `tool/notification_analytics_schema.sql`

**RPC functions (optional but useful)**

- `public.get_unread_count(user_uuid uuid)`
  - Source: `tool/notifications_schema.sql`
  - Can power the bell badge count efficiently

**Schema conflict resolution (recommended path)**

If you want both:

- Keep `public.notifications` = per-user inbox (from `tool/notifications_schema.sql`)
- Rename campaign/template table in `tool/push_notification_schema.sql` (e.g. `notification_campaigns`) before applying it

---

### B) Flutter — Notification Center UI

**Current consumer notifications page**

- `lib/features/notifications/notifications_screen.dart`
  - Today: reads from `AnnouncementsStore` (announcements)
  - Target: read from `public.notifications` (per-user)

**Recommended new repo structure additions**

Create a minimal per-user notification data layer under `lib/features/notifications/`:

- `lib/features/notifications/repositories/user_notifications_repository.dart`
  - `listMyNotifications(limit, offset)` → `from('notifications')...order('created_at')`
  - `markRead(id)` / `markAllRead()` → update `read=true`, `read_at=now()`
  - `countUnread()` → RPC `get_unread_count` or query `read=false`

- `lib/features/notifications/models/user_notification.dart`
  - Parse Supabase rows: `id,title,body,type,data,createdAt,read`

Then wire the UI:

- Update `lib/features/notifications/notifications_screen.dart`
  - add pull-to-refresh (`RefreshIndicator`)
  - render read/unread states
  - on tap: `markRead` then route based on type/data

---

### C) Flutter — Bell Badge + Navigation

**Bell entry point**

- `lib/features/shell/app_shell.dart`
  - Today:
    - badge count = `AnnouncementsStore.instance.items.length`
    - tap opens `NotificationsScreen` (announcements)
  - Target:
    - badge count = unread notifications for current user
    - tap opens Notification Center (per-user)

**Optional quick preview sheet**

- `_TopBarNotificationsSheet` is defined in `lib/features/shell/app_shell.dart` and already queries `from('notifications')`
  - Target:
    - either wire it (long-press on bell)
    - or remove/replace with the main center screen

---

### D) Push → Database persistence

Goal: any push notification sent should also create a `public.notifications` row for the user(s).

Where this likely happens:

- Backend/Edge/Functions responsible for sending FCM
- FCM payload should include enough `type` + `data` to route in-app

Client responsibilities:

- `lib/features/notifications/services/fcm_service.dart`
  - Already logs opens via `NotificationAnalyticsService`
  - Ensure payload includes `type`, and ideally `notification_id` (the DB row id)

---

## End-to-End Flow (Target)

```text
Event occurs
  |
  | (backend)
  v
Insert into public.notifications (per-user row)
  |
  +--> (optional) send push via FCM (includes {id,type,data})
  |
  v
Flutter
  - bell badge queries unread count
  - Notification Center lists rows
  - tap marks read + routes to target screen
```

---

## Suggested Implementation Order (Small, Safe Steps)

1) Consumer UI reads from `public.notifications` (keep announcements separate)
2) Bell badge uses unread count (`get_unread_count`)
3) Implement mark-as-read + mark-all
4) Implement routing per `type`/`data` (incrementally)
5) Ensure backend persists notifications rows for key events

---

## Notes / Known Drift to Watch

- There are **two incompatible `public.notifications` schemas** in `tool/`.
- Some docs in `NOTIFICATION_SYSTEM_INDEX.md` reference files that are not present under `lib/features/notifications/` in this checkout.

If you want, I can also:
- generate a Supabase migration plan (rename tables to remove conflicts), and/or
- implement steps (1)–(3) in Flutter so consumers get a real per-user notification center.
