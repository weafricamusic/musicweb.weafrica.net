// Native (Android/iOS/macOS) stub for AgoraService.
// Does NOT import dart:html or dart:js_util.
import 'package:flutter/foundation.dart';
import 'agora_service_shared.dart';

class AgoraService {
  bool _initialized = false;
  bool _joined = false;

  final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<int?> remoteUid = ValueNotifier<int?>(null);

  dynamic get engine => null;
  dynamic get localVideoTrack => null;
  dynamic get remoteVideoTrack => null;
  bool get isBroadcaster => false;

  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('🟢 AgoraService initialized (native stub)');
    _initialized = true;
  }

  Future<void> joinChannel({
    required String channelName,
    required AgoraRole role,
    String? token,
    int? uid,
  }) async {
    debugPrint('🟡 AgoraService: joinChannel called for $channelName (native stub)');
    if (!_initialized) await initialize();
    _joined = true;
    isJoined.value = true;
  }

  Future<void> leaveChannel() async {
    if (_joined) {
      _joined = false;
      isJoined.value = false;
      debugPrint('✅ AgoraService: left channel (native stub)');
    }
  }

  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
  }

  Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
  }

  Future<void> switchCamera() async {}

  /// Web-only: attaches video to DOM element. No-op on native.
  void attachLocalVideoToElement(String elementId) {}

  /// Web-only: creates DOM overlay for local video. No-op on native.
  void createVideoOverlay() {}

  /// Web-only: creates DOM overlay for remote video. No-op on native.
  void createRemoteVideoOverlay() {}

  /// Web-only: removes DOM overlay. No-op on native.
  void removeVideoOverlay() {}

  Future<void> dispose() async {
    await leaveChannel();
    isJoined.dispose();
    isMuted.dispose();
    isVideoEnabled.dispose();
    remoteUid.dispose();
  }
}