# WeAfrica Music — Consumer Home Screen (Blueprint + Backend Bindings)

This document is a **developer blueprint** for the Consumer Home screen.

It covers:
- **What is on the screen** (sections + components)
- **What happens on interaction** (taps, navigation, playback)
- **Where the data comes from** (**Supabase backend** tables + repository methods)

See also:
- `docs/CONSUMER_TABS_BACKEND_BINDINGS.md` (Music / Live / Library backend bindings)

> Source of truth in code:
> - Home UI: `WeAfricaHomeV2Page` in `lib/features/home/weafrica_home_v2.dart`
> - Shell AppBar + Bottom Nav: `AppShell` in `lib/features/shell/app_shell.dart`

---

## 1) Visual layout map (as implemented)

```
┌───────────────────────────────────────────────────────────┐
│ Top App Bar (global, all tabs except Pulse)                │
│  WEAFRICA MUSIC (tappable → goes Home)                     │
│  [Search] [Notifications(+badge)] [Coins(balance)] [Profile]│
├───────────────────────────────────────────────────────────┤
│ Scrollable Home Body (Consumer)                            │
│                                                           │
│ (Optional) Announcements banner (“WEAFRICA UPDATE”) + CTA  │
│   (Watch Live)                                             │
│                                                           │
│ Live/Event strip (single card)                             │
│  - shows LIVE or EVENT + title + CTA (Join/View)           │
│                                                           │
│ Stats pills row                                            │
│  [🔥 trending count] [🆕 new count] [▶ videos count]        │
│                                                           │
│ Country chips (horizontal)                                 │
│  [🇲🇼 Malawi] [🇳🇬 Nigeria] [🇿🇦 South Africa] [🇰🇪 Kenya]      │
│  [🇬🇭 Ghana]                                                │
│                                                           │
│ Recent played (grid, up to 8 items)                        │
│  [cover + title] [cover + title]                           │
│  [cover + title] [cover + title]                           │
│                                                           │
│ Featured (horizontal scroll)                               │
│  [Artist card] [Artist card] [Artist card] ...             │
│                                                           │
│ Recommended for you (horizontal scroll)                    │
│  [Track card] [Track card] [Track card] ...                │
│                                                           │
│ {Country} Top 10 (vertical list)                            │
│  1. Track row                                               │
│  2. Track row                                               │
│  ...                                                       │
│                                                           │
│ Hot videos (horizontal strip) + “Open feed →”              │
│  [Video card] [Video card] ...                             │
│                                                           │
├───────────────────────────────────────────────────────────┤
│ Mini Player (only on Home, when music is playing)          │
└───────────────────────────────────────────────────────────┘

Bottom Navigation (global)
  Home | Pulse | Music | Live | Library
```

---

## 2) Interactions & micro-behaviors (current)

### Top App Bar (global)
- **Title tap**: returns to Home.
- **Search icon**: opens Search screen.
- **Notifications icon**: opens Notifications screen; shows badge count.
- **Coins pill**: opens Wallet.
- **Profile icon**: opens Profile.

### Country chips
- Tap a chip → persists selection and **reloads Home data** for that country.
- Currently limited to **MW/NG/ZA/KE/GH** (hard-coded in Home UI).

### Recent played
- Tap an item → fetches the full track from backend (by id) and starts playback.
- Playback starts with a **queue built from the other visible recent items** so **Next works**.

### Featured
- Tap an artist card → opens public artist profile.

### Recommended for you
- Tap a track card → starts playback with a **queue of the other tracks in the strip**.

### Top 10
- Tap a row → starts playback with a queue (rest of list).

### Hot videos
- Tap “Open feed →” → opens Pulse feed.

### Mini Player (music)
- Only visible when a track is active.
- Next/Prev/Seek are handled by the shared `PlaybackController` + `WeAfricaAudioHandler`.

---

## 3) Backend data sources (Supabase)

### Bootstrapping (Supabase must be initialized)
Supabase is initialized during app bootstrap:
- `lib/app/bootstrap/bootstrap_app.dart` calls `Supabase.initialize(url, anonKey)`.

If Supabase is not configured correctly:
- the app shows a setup/error screen instead of silently using fake data.

### Section → repository → table mapping

#### Trending / Top 10
- UI uses: `TracksRepository.trendingByCountry(countryCode)`
- Supabase table: `songs`
- Filter/sort: `country_code == CC`, ordered by `plays_count` (with schema fallbacks)
- Cache: results are stored locally (SharedPreferences) for faster next launch.

#### New releases
- UI uses: `TracksRepository.newReleasesByCountry(countryCode)` (internally `byCountry`)
- Supabase table: `songs`
- Filter/sort: `country_code == CC`, ordered by `created_at desc`
- Cache: stored locally for faster next launch.

#### Recommended for you
- UI uses: `_buildRecommended()` in Home
- Supabase tables:
  - `recent_contexts` (to find user’s latest played track)
  - `songs` (to fetch track + query by `genre` and by `country_code`)

#### Recent played
- UI uses: `RecentContextsService.fetchQuickAccess(limit: 8)`
- Supabase table: `recent_contexts`
- Keying:
  - If logged in: uses Supabase auth user id
  - If logged out: generates a device-scoped UUID and uses it as `user_id`
- When you play a track, the app writes back via `RecentContextsService.upsertContext(...)`.

#### Featured artists
- UI uses: `_buildFeaturedArtists()` → `CreatorsRepository.listFeaturedArtists(...)`
- Supabase tables (depending on schema availability):
  - `featured_artists`
  - `artists`
  - fallback: `creator_profiles`

#### Hot videos
- UI uses: `_buildHotVideos()` → `VideosRepository.latestByCountry(...)`
- Supabase table: `videos`
- Filter/sort: `country_code == CC`, ordered by `created_at desc` (with fallbacks)

#### Live / events strip
- UI uses: `LiveEventsRepository.list(kind: 'live'|'event', countryCode: CC)`
- Supabase table: `events`

---

## 4) Deployment note (Web)

For Flutter Web, backend access depends on compile-time env values:
- Supabase URL + anon key must be provided via `--dart-define-from-file`.

Repo build helper:
- `tool/build_web_vercel.sh` expects `assets/config/supabase.env.json` or env vars (`WEAFRICA_ENV_JSON_BASE64` / `WEAFRICA_ENV_JSON`).

---

## 5) RLS / policies (required)

To allow Consumer browsing, Supabase must allow read access for the client (anon/auth):
- `songs`, `videos`, `events`, `creator_profiles` (and optionally `artists`, `featured_artists`)
- `recent_contexts` needs policies consistent with how you want to handle:
  - authenticated users (user_id = auth.uid)
  - anonymous/device users (device UUID stored as user_id)

If RLS blocks reads, most repository methods throw friendly errors describing what to fix.

Note: `TracksRepository`, `VideosRepository`, and `CreatorsRepository` surface friendly Supabase/RLS errors; `LiveEventsRepository` logs failures and returns an empty list (best-effort).
