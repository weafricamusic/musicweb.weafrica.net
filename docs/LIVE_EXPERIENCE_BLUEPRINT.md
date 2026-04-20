# WeAfrica Music Live Experience Blueprint

## 1. Routing and role detection

Goal: always send creators to host UI and consumers to fan UI.

Decision order:
1. Resolve role (`consumer`, `artist`, `dj`).
2. Resolve session type (`battle` or `solo`).
3. Resolve broadcaster status:
   - creator role (`artist` or `dj`) is broadcaster intent
   - current user equals host id is broadcaster
   - battle participant list contains current user is broadcaster
4. Route:
   - battle + broadcaster => `ProfessionalBattleScreen`
   - battle + audience => `ConsumerBattleScreen`
   - solo + broadcaster => `SoloLiveStreamScreen`
   - solo + audience => `LiveWatchScreen`

QA logging requirement:
- emit routing logs for each entry:
  - `LiveSession: userId=..., role=..., isBroadcaster=..., sessionType=battle|solo`

## 2. Artist and DJ host live screen

Purpose: full stream control with realtime feedback.

Top status area:
- live badge
- viewer count
- earnings summary
- goal progress bars (flowers, diamonds, drum power)

Stage area:
- main camera/battle stage
- opponent PiP/split view in battle
- timeline and status indicators

Host controls:
- invite guest/opponent
- switch camera
- mic mute/unmute
- camera video on/off
- comments overlay toggle
- crowd boost toggle
- drop challenger action
- end live action

Interaction surfaces:
- comments overlay (toggleable)
- gifts and reactions from audience
- battle control tray for host-only actions

DJ-specific additions:
- DJ console strip for queue and transport controls (play/pause/skip)
- level/effects controls where available

## 3. Fan and consumer live screen

Purpose: watch and engage without host powers.

Available:
- fullscreen stream watch
- chat input
- likes and reactions
- send gifts
- read-only live status and battle context

Not available:
- no camera switch
- no mic toggle
- no end live
- no battle moderation controls

## 4. Battle mode differences

Host/artist/dj:
- editable and actionable controls
- opponent and queue management
- full room metrics

Fan/consumer:
- read-only battle state
- engagement actions only (chat, like, gift)

## 5. QA checklist

Routing checks:
1. Artist enters battle -> host screen opens.
2. DJ enters battle -> host screen opens.
3. Consumer enters battle -> fan screen opens.
4. Host enters solo live -> solo host screen opens.
5. Consumer enters solo live -> watch screen opens.

Control checks:
1. Host sees end live and device controls.
2. Consumer does not see host-only controls.
3. Comments overlay can be toggled by host.
4. Battle invite and challenger actions are host-only.

Logging checks:
1. Verify one routing log per screen entry.
2. Verify role and `isBroadcaster` values match expected branch.

## 6. Implementation references

Core router and role split:
- `lib/features/live/live_screen.dart`

Battle host screen:
- `lib/features/live/screens/professional_battle_screen.dart`

Solo host screen:
- `lib/features/live/screens/solo_live_stream_screen.dart`

Fan watch screen:
- `lib/features/live/screens/live_watch_screen.dart`

Battle fan screen:
- `lib/features/live/screens/consumer_battle_screen.dart`
