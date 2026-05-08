import 'package:flutter/foundation.dart';
import '../core/enums/live_role.dart';

/// Abstract live engine interface shared across platforms.
///
/// Mobile implementation uses `agora_rtc_engine` native SDK.
/// Web implementation uses Agora Web SDK via `dart:html` / `dart:js_util`.
abstract class LiveEngineInterface {
  // ─── Lifecycle ───────────────────────────────────────────

  /// Platform-specific engine instance (e.g., native RtcEngine or web Agora client).
  dynamic get engine;

  Future<void> initialize();
  Future<void> dispose();

  // ─── Connection ──────────────────────────────────────────

  Future<void> joinChannel({
    required String channelName,
    required LiveRole role,
    String? token,
    int? uid,
  });

  Future<void> leaveChannel();

  // ─── Controls ───────────────────────────────────────────

  Future<void> toggleMute();
  Future<void> toggleVideo();
  Future<void> switchCamera();

  // ─── Observables ────────────────────────────────────────

  ValueNotifier<bool> get isJoined;
  ValueNotifier<bool> get isMuted;
  ValueNotifier<bool> get isVideoEnabled;
  ValueNotifier<int?> get remoteUid;

  /// onCreateVideoOverlay: attaches camera video to a platform view.
  /// For mobile this creates a `AgoraVideoView`, for web it creates a DOM overlay.
  void createLocalVideoOverlay();
  void createRemoteVideoOverlay();
  void removeVideoOverlay();
}