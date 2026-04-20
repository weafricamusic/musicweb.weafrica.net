# WeAfrica LIVE — Premium Stage (Internal PRD, 1 page)

## Goal
Build a calm, high-trust live music venue where:
- Artists & DJs feel professional.
- Fans feel intentional (not overstimulated).
- Quality (audio, pacing, curation) is the brand.

## Non-goals (explicit)
- Endless dopamine feeds.
- Reaction spam / visual clutter.
- Accidental / low-effort lives.
- Building “pro studio” depth before baseline audio consistency.
- Any Agora credential / secret changes (locked).

## Primary users
1) Creators (Artists & DJs): reliability, respect, monetization, stagecraft.
2) Fans/listeners: trusted discovery + live moments worth time.

## Experience principles (hard rules)
- One primary action per screen.
- Max 2 overlay zones at any time.
- Motion is intentional + brief.
- Dark-first “stage/studio” aesthetic.
- Monetization is present but restrained.

## Phase 1 (Premium Feel) — ship fast
### Creator Pre‑Live (mandatory)
- Camera preview (no auto-join).
- Mic + camera controls + switch camera.
- Live title.
- Clear “Go Live” confirmation.

### Audience Live View (calm defaults)
- Main stage video (no clutter).
- Audience Layer (collapsed by default): chat + comment input behind a toggle.
- Applause (rate-limited feel): subtle, no screen takeover.
- Support (coins/gifts): secondary action.

### Stream hygiene (simple)
- Small health indicator (green/yellow/red).
- Audio level hint (“low / peaking”).

## Discovery surfaces (stable)
1) Editor’s Desk
2) Mood / BPM / Energy
3) By Country / City (Malawi-first)
4) Listening intent (Headphones / Car / Club)

Algorithm supports these pillars; it does not replace them.

## Monetization
- Coins: subtle support.
- Subscriptions: identity/status.
- Pay-per-view: events only.
- Tips: appreciation, not noise.

No intrusive ads inside live streams.

## Success metrics (Phase 1)
- Creator go-live completion rate ↑
- Average live duration ↑
- Audio-related complaints ↓
- Repeat lives per creator/week ↑

## Screen-by-screen mapping (current Flutter)
### Creator entry
- `CreatorDashboardScreen` launches `LiveScreen` with pre-live confirmation.

### Live experience
- `LiveScreen`
  - Pre-live overlay for creators (title + mic/cam + switch + Go Live).
  - Audience Layer toggle: collapse chat + comment UI by default for viewers.
  - Applause replaces floating hearts (restrained visual language).

### Viewer entry
- `LiveEventsTab` can continue to join immediately (viewer intent), while Creator flows remain confirm-first.

## Next execution (tickets)
1) Add “stream health” dot + label in top overlay (no Agora config changes).
2) Add basic audio hint (simple first, then deeper meter later).
3) Clean naming across remaining entry points (Stage Live / Spin Live).
4) Post-live summary polish: allow ‘Save highlight’ and ‘Share replay’ stubs.
