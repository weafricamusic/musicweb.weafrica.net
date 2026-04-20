import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_handler.dart';

WeAfricaAudioHandler? _weafricaAudioHandler;

/// Global audio handler used across the app.
///
/// Prefer calling [initWeAfricaAudio] during startup.
WeAfricaAudioHandler get weafricaAudioHandler {
  final handler = _weafricaAudioHandler;
  if (handler == null) {
    throw StateError(
      "WeAfrica audio has not been initialized. Call initWeAfricaAudio() before using weafricaAudioHandler.",
    );
  }
  return handler;
}

bool get isWeAfricaAudioInitialized => _weafricaAudioHandler != null;

WeAfricaAudioHandler? get maybeWeafricaAudioHandler => _weafricaAudioHandler;

Future<WeAfricaAudioHandler> initWeAfricaAudio() async {
  final existing = _weafricaAudioHandler;
  if (existing != null) return existing;

  try {
    final handler = await AudioService.init<WeAfricaAudioHandler>(
      builder: () => WeAfricaAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.weafrica.music.playback',
        androidNotificationChannelName: 'WeAfrica Music',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidStopForegroundOnPause: true,  // Better performance
      ),
    );

    // OPTIMIZED: Disable crossfade for faster transitions (optional)
    await handler.configureCrossfade(
      enabled: false,  // Set to false for faster transitions
    );

    _weafricaAudioHandler = handler;
    return handler;
  } catch (e, st) {
    // If background audio initialization fails (e.g. hot-restart edge cases or
    // platform/plugin issues), fall back to a foreground-only handler so the UI
    // doesn't crash.
    debugPrint('initWeAfricaAudio failed, using fallback handler: $e');
    debugPrintStack(stackTrace: st, maxFrames: 200);

    final fallback = WeAfricaAudioHandler();
    _weafricaAudioHandler = fallback;
    return fallback;
  }
}