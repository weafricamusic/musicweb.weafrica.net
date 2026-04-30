# Web Voice Calling Fix - Agora SDK Integration

## Problem
The web Agora Voice Calling was not working because the Agora Web SDK script was missing from the web `index.html` file. The application was only configured for video calling using the native `agora_rtc_engine` package, which doesn't work on web.

## Solution
Implemented a comprehensive web voice calling solution with the following components:

### 1. Added Agora Web SDK to `web/index.html`
```html
<!-- Agora Web SDK for Voice and Video Calling -->
<script src="https://download.agora.io/sdk/release/AgoraRTC_N-4.24.3.js"></script>
```

This loads the Agora Web SDK version 4.24.3 (latest) which supports both voice and video calling on web browsers.

### 2. Created `lib/features/live/services/agora_voice_service_web.dart`
A dedicated voice calling service for web that:
- Uses JavaScript interop to interact with the Agora Web SDK
- Supports both host (broadcaster) and audience (listener) roles
- Provides event streams for connection state, user join/leave
- Handles audio track management (mute/unmute)
- Properly cleans up resources on dispose

**Key Features:**
- `joinVoiceChannel()` - Join as host with microphone
- `joinAsAudience()` - Join as listener only
- `toggleMute()` - Mute/unmute local audio
- Event streams for real-time updates
- Automatic SDK loading with retry logic

### 3. Created `lib/features/live/screens/voice_call_screen_web.dart`
A complete UI for voice calling on web with:
- Modern gradient background design
- Call duration timer
- Mute/unmute controls
- End call button
- Connection status indicators
- Error handling with retry capability

### 4. Enhanced `lib/features/live/services/agora_rtc_service.dart`
Added voice-only mode support:
- New `voiceOnly` parameter in `initialize()`
- New `initializeVoiceOnly()` convenience method
- Disables video tracks when in voice-only mode
- Optimizes audio profile for voice communication
- Handles permissions appropriately (no camera needed for voice-only on web)

**Voice-Only Configuration:**
```dart
await agoraRtcService.initializeVoiceOnly(
  appId: appId,
  isHost: true,
  channelId: channelId,
  token: token,
  userId: userId,
);
```

## Usage

### For Voice Calls on Web
```dart
// Use the web-specific service
final voiceService = AgoraVoiceServiceWeb();

// Join as host
await voiceService.joinVoiceChannel(
  appId: AppEnv.agoraAppId,
  channelId: channelId,
  token: token,
);

// Or join as audience
await voiceService.joinAsAudience(
  appId: AppEnv.agoraAppId,
  channelId: channelId,
  token: token,
);
```

### For Voice-Only Mode with Native SDK
```dart
// Use the enhanced RTC service with voiceOnly flag
await agoraRtcService.initializeVoiceOnly(
  appId: appId,
  isHost: isHost,
  channelId: channelId,
  token: token,
  userId: userId,
);
```

### Using the Voice Call Screen
```dart
// Navigate to voice call screen (web only)
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => VoiceCallScreenWeb(
      channelId: channelId,
      hostName: hostName,
      isHost: isHost,
      token: token,
    ),
  ),
);
```

## Technical Details

### Agora SDK Versions
- **Web SDK**: 4.24.3 (loaded via CDN)
- **Native SDK**: 6.5.3 (via `agora_rtc_engine` package)
- **RTM SDK**: 1.6.3 (via `agora_rtm` package)

### Platform Detection
The web-specific code uses `kIsWeb` from `package:flutter/foundation.dart` to ensure it only runs on web platforms.

### Permissions
- **Web**: Browser handles microphone permissions natively when audio tracks are created
- **Mobile/Desktop**: Uses `permission_handler` package for camera and microphone permissions

### Audio Optimization
Voice-only mode uses:
- Audio Profile: `audioProfileSpeechStandard`
- Audio Scenario: `audioScenarioChatroom`
- These settings optimize bandwidth and quality for voice communication

## Testing
To test the voice calling functionality:

1. Ensure `AGORA_APP_ID` is configured in `assets/config/supabase.env.json`
2. Run the web app: `flutter run -d chrome`
3. Navigate to a live stream or voice call
4. The Agora Web SDK will automatically load and handle the voice connection

## Future Improvements
1. Consider migrating from `dart:js` to `dart:js_interop` for better type safety
2. Add echo cancellation and noise suppression settings
3. Implement audio level visualization
4. Add support for multiple simultaneous voice channels
5. Add recording capability for voice calls

## Files Modified/Created
- ✅ `web/index.html` - Added Agora Web SDK script
- ✅ `lib/features/live/services/agora_voice_service_web.dart` - New voice service for web
- ✅ `lib/features/live/screens/voice_call_screen_web.dart` - New voice call UI
- ✅ `lib/features/live/services/agora_rtc_service.dart` - Added voice-only mode support

## Compatibility
- ✅ Web (Chrome, Firefox, Safari, Edge)
- ✅ Mobile (iOS, Android) - via voice-only mode in AgoraRtcService
- ✅ Desktop (Windows, macOS, Linux) - via voice-only mode in AgoraRtcService

## References
- [Agora Web SDK Documentation](https://docs.agora.io/en/video-calling/get-started/get-started-sdk)
- [Agora Voice SDK for Web](https://docs.agora.io/en/voice-call/get-started/get-started-sdk)
- [Flutter Web Interop](https://dart.dev/interop/js-interop)