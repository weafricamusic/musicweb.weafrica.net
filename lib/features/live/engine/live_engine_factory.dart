import 'package:flutter/foundation.dart';
import 'live_engine_interface.dart';
import '../../../data/services/agora_service.dart';
import 'package:weafrica_music/features/live/core/enums/live_role.dart';

/// Creates the platform-appropriate engine via the existing AgoraService
/// which already handles platform separation internally.
class LiveEngineFactory {
  static LiveEngineInterface create() {
    final service = AgoraService();
    return _AgoraServiceAdapter(service);
  }
}

/// Adapter wrapping AgoraService into LiveEngineInterface.
class _AgoraServiceAdapter implements LiveEngineInterface {
  final AgoraService _service;

  _AgoraServiceAdapter(this._service);

  @override
  dynamic get engine => _service.engine;

  @override
  ValueNotifier<bool> get isJoined => _service.isJoined;
  @override
  ValueNotifier<bool> get isMuted => _service.isMuted;
  @override
  ValueNotifier<bool> get isVideoEnabled => _service.isVideoEnabled;
  @override
  ValueNotifier<int?> get remoteUid => _service.remoteUid;

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<void> joinChannel({required String channelName, required LiveRole role, String? token, int? uid}) {
    return _service.joinChannel(
      channelName: channelName,
      role: role == LiveRole.broadcaster ? AgoraRole.broadcaster : AgoraRole.audience,
      token: token,
      uid: uid,
    );
  }

  @override
  Future<void> leaveChannel() => _service.leaveChannel();
  @override
  Future<void> toggleMute() => _service.toggleMute();
  @override
  Future<void> toggleVideo() => _service.toggleVideo();
  @override
  Future<void> switchCamera() => _service.switchCamera();

  @override
  void createLocalVideoOverlay() => _service.createVideoOverlay();
  @override
  void createRemoteVideoOverlay() => _service.createRemoteVideoOverlay();
  @override
  void removeVideoOverlay() => _service.removeVideoOverlay();

  @override
  Future<void> dispose() => _service.dispose();
}
