# Fix Console Spam & Network Issues from Flutter Logs

## Status: ✅ Plan approved, implementation started

## Steps

### 1. ✅ Stop Track Artwork Spam Logging
File: `lib/features/tracks/track.dart`  
- Guarded `debugPrint('📀 Track...')` blocks with `if (kDebugMode && _debugTrackCount++ < 50)`
- Added static counter reset method for debug sessions.

### 2. ⏳ Reduce BattleInviteListener Verbosity  
File: `lib/features/live/services/battle_invite_listener.dart`  
[PENDING] Log only errors, add connectivity guard.

### 3. ⏳ Network Guards for FCM Mirror  
File: `lib/services/notification_service.dart`  
[PENDING] Connectivity check before Supabase writes.

### 4. ⏳ Create ConnectivityService  
File: `lib/services/connectivity_service.dart` [NEW]  
[PENDING] Singleton stream.

### 5. ⏳ Integrate in Listeners  
Files: battle_invite_listener.dart + notification_service.dart  
[PENDING] Pause retries offline.

### 6. ⏳ Test & Verify  
- `flutter run` → no spam, graceful offline  
- `flutter analyze` clean

### 7. ✅ COMPLETE  
`attempt_completion` with summary + demo command.

---

**Next**: Step 2 - Edit battle_invite_listener.dart
