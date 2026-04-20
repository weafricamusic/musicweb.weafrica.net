# WeAfrica Music — Consumer Tabs (Backend Bindings)

This document maps the **consumer-facing tabs** (Music / Live / Library) to the **actual backend sources** they read/write.

Scope:
- Tabs as wired in `AppShell` (`lib/features/shell/app_shell.dart`).
- Focus: **Music**, **Live**, **Library**.

Backends used by these tabs:
- **Supabase PostgREST** (direct `.from('table')...` queries via `supabase_flutter`).
- **Supabase Edge API** under `/api/*` (HTTP calls to `ApiEnv.baseUrl`), implemented in `supabase/functions/api/index.ts`.
- **Firebase Auth** (some `/api/*` routes require `Authorization: Bearer <Firebase ID token>`).

---

## 1) Music tab

**UI entrypoint**
- `MusicTab` in `lib/features/music/music_tab.dart`

**What it loads**
1) **Latest tracks / Search results**
- Code: `TracksRepository().latest(...)` and `TracksRepository().search(...)`
- Backend: **Supabase table** `songs`
- Notes:
  - `search()` attempts to query `songs` plus an embedded `artists(...)` relation; it falls back to title-only search if artist columns/relations are missing.

2) **Latest published albums**
- Code: `AlbumsRepository().latestPublished(...)`
- Backend: **Supabase table** `albums` (query adapter tolerates schema drift)

3) **Album → tracks**
- Primary path (HTTP):
  - Code: `_fetchAlbumTracks()` → `GET ${ApiEnv.baseUrl}/api/albums/:id/tracks?limit=...` using `FirebaseAuthedHttp.get(..., includeAuthIfAvailable: true, requireAuth: false)`
  - Backend: **Supabase Edge API** route `/api/albums/:id/tracks` implemented in `supabase/functions/api/index.ts`
  - Data source: reads **Supabase table** `songs` filtered by `album_id`, with best-effort publish gates (status/is_active/approved/is_public/is_published when present).
- Fallback path (direct query):
  - Code: direct Supabase query `.from('songs')...eq('album_id', id)`

---

## 2) Live tab

**UI entrypoint**
- `LiveFeedScreen` in `lib/features/live/screens/live_feed_screen.dart`

**What it loads**
1) **Discovery (Live Now / Upcoming / Replays)**
- Code: `LiveDiscoveryService` in `lib/features/live/services/live_discovery_service.dart`
- Backend: **Supabase tables**
  - `live_sessions` (discovery of currently-live sessions via `is_live = true`)
  - `live_battles` (upcoming + replay listings)
- Notes:
  - Uses `trending_score` when present (falls back to viewer_count ordering).

2) **Subscribe to reminders**
- Code: `POST /api/live/notify/subscribe` in `LiveFeedScreen._subscribeToReminders()`
- Backend: **Supabase Edge API** route `/api/live/notify/subscribe`
- Auth: requires **Firebase ID token**
- Data source: writes to **Supabase table** `live_notifications` (`user_uid = Firebase uid`) via admin client.

3) **Watch / Join a live session**
- Code: `LiveSessionService().joinSession(channelId, userId)`
- Backends:
  - **Supabase table** `live_sessions` (lookup by `id` then fallback to `channel_id`)
  - **Supabase table** `profiles` (embedded join `profiles!host_id(display_name)` when available)
  - **Edge API** `POST /api/agora/token` via `AgoraTokenApi.fetchRtcToken(...)` to mint Agora RTC tokens
  - For battle-style sessions: **Edge API** `GET /api/battle/status?battle_id=...` (used when a `weafrica_battle_` channel does not have a matching `live_sessions` row)

4) **Creator presence (not consumer UI, but impacts discovery)**
- Code: `LiveSessionService.createSession/heartbeat/endLive` → `LiveSessionsApi`
- Backend: **Edge API routes**
  - `POST /api/live/sessions/start`
  - `POST /api/live/sessions/heartbeat`
  - `POST /api/live/sessions/end`
- Auth: requires **Firebase ID token**
- Purpose: keeps `live_sessions` accurate so consumers see correct Live Now rows.

---

## 3) Library tab

**UI entrypoint**
- `LibraryTab` in `lib/features/library/screens/library_tab.dart`

Library is a mix of:
- **Backend-backed metadata** (Supabase tables)
- **Local-only state** (likes + downloaded file paths)

### 3.1 Tracks

1) **Liked tracks**
- Code: `LibraryService.getLikedTracks()`
- Storage of “liked ids”: **local** `SharedPreferences` key `liked_tracks`
- Track metadata resolution: `TracksRepository.getById(id)` → **Supabase table** `songs`

2) **Recently played**
- Code: `LibraryRecentService.getRecentlyPlayed()`
- Backends:
  - `RecentContextsService.fetchQuickAccess()` → **Supabase table** `recent_contexts`
  - Then resolves track metadata via `TracksRepository.getById(...)` → **Supabase table** `songs`
- User identity note:
  - `recent_contexts.user_id` is **Supabase auth user id** if present; otherwise a **device UUID** stored locally.

3) **Downloaded tracks**
- Code: `LibraryDownloadService` (platform-specific)
- Storage: **local filesystem** on mobile/desktop (`library_download_service_io.dart`), not supported on web (`library_download_service_stub.dart`)
- Track metadata resolution still uses **Supabase** (`TracksRepository.getById` → `songs`).

### 3.2 Albums

**Saved albums**
- Code: `LibraryService.getSavedAlbums()`
- Primary backend path (authenticated):
  - **Supabase table** `saved_albums` joined to `albums` (`select('albums!inner(*)')`)
  - Uses **FirebaseAuth uid** as `saved_albums.user_id`
- Fallback path (if table missing / RLS blocks / not authenticated):
  - `AlbumsRepository.latestPublished()` → **Supabase table** `albums`

### 3.3 Playlists

**My playlists list + playlist contents**
- Code: `PlaylistsRepository` in `lib/features/playlists/playlists_repository.dart`
- Backends:
  - `playlists` (list/create/delete)
  - `playlist_songs` joined with `songs` (legacy compatibility)
  - `playlist_tracks` joined with `tracks` (legacy compatibility)
- User identity note:
  - Uses **FirebaseAuth uid** if signed in; otherwise a **device UUID** stored locally.
  - Includes compatibility logic if the DB expects UUID user ids (derives a stable UUIDv5).

### 3.4 Artists directory (inside Library)

- Code: `CreatorsDirectoryTab` → `CreatorsRepository`
- Backend: **Supabase tables** `creator_profiles` (and fallbacks via `artists` / `featured_artists` when present).

---

## 4) RLS / policy checklist (practical)

To make these tabs work for consumers, Supabase must allow:

**Public/anon reads (consumer browsing)**
- `songs` (tracks)
- `albums` (album browsing)
- `live_sessions`, `live_battles` (live discovery)
- `profiles` (at least the columns used for display names)
- `creator_profiles` (artist directory)

**User-scoped data (requires INSERT/UPDATE/DELETE policies as appropriate)**
- `recent_contexts` (upsert + select for a `user_id`)
- `saved_albums` (select/insert/delete for Firebase uid in `user_id`)
- `playlists`, `playlist_tracks` / `playlist_songs` (select/insert/delete per `user_id`)

**Edge API writes**
- `/api/live/*` and `/api/agora/*` are implemented server-side in `supabase/functions/api/index.ts` and typically use an admin Supabase client for writes; the client mostly needs **read** access to discovery tables.
