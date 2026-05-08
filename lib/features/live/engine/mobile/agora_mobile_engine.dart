import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart'
    if (dart.library.html) '../../../stubs/agora_rtc_engine_stub.dart';
import '../live_engine_interface.dart';
import '../../core/enums/live_role.dart';
import '../../core/constants/agora_constants.dart';
import '../../../../data/services/agora_token_service.dart';

/// Android / iOS engine using the native `agora_rtc_engine` plugin.
class AgoraMobileEngine implements LiveEngineInterface {
  RtcEngine? _engine;
  bool _initialized = false;
  bool _joined = false;
  bool _isBroadcaster = false;

  final _tokenService = AgoraTokenService();

  @override
  dynamic get engine => _engine;

  @override
  final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  @override
  final ValueNotifier<int?> remoteUid = ValueNotifier<int?>(null);

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('🟢 [Mobile] Initializing Agora RTC Engine...');

    // Validate App ID before SDK initialization
    AgoraConstants.validateAppId();

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: AgoraConstants.appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    await _engine!.enableVideo();
    await _engine!.enableAudio();

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('✅ [Mobile] Joined channel: ${connection.channelId}');
        _joined = true;
        isJoined.value = true;
      },
      onUserJoined: (connection, rUid, elapsed) {
        debugPrint('👤 [Mobile] Remote user joined: $rUid');
        remoteUid.value = rUid;
      },
      onUserOffline: (connection, rUid, reason) {
        debugPrint('👋 [Mobile] Remote user left: $rUid');
        remoteUid.value = null;
      },
      onError: (err, msg) {
        debugPrint('❌ [Mobile] Agora error: $err — $msg');
      },
    ));

    _initialized = true;
    debugPrint('✅ [Mobile] Agora RTC Engine initialized');
  }

  @override
  Future<void> joinChannel({
    required String channelName,
    required LiveRole role,
    String? token,
    int? uid,
  }) async {
    if (!_initialized) await initialize();

    _isBroadcaster = (role == LiveRole.broadcaster);
    final userId = uid ?? 0;

    // Fetch token from backend if not provided
    String finalToken = token ?? '';
    if (finalToken.isEmpty) {
      finalToken = await _fetchToken(channelName, userId, role);
    }

    final clientRole = _isBroadcaster
        ? ClientRoleType.clientRoleBroadcaster
        : ClientRoleType.clientRoleAudience;

    await _engine!.setClientRole(role: clientRole);

    if (_isBroadcaster) {
      await _engine!.startPreview();
    }

    await _engine!.joinChannel(
      token: finalToken,
      channelId: channelName,
      uid: userId,
      options: ChannelMediaOptions(
        autoSubscribeVideo: true,
        autoSubscribeAudio: true,
        publishCameraTrack: _isBroadcaster,
        publishMicrophoneTrack: _isBroadcaster,
        clientRoleType: clientRole,
      ),
    );
  }

  /// Fetch a short-lived RTC token from the production backend.
  Future<String> _fetchToken(String channelName, int uid, LiveRole role) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('User not authenticated. Cannot fetch Agora token.');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Firebase ID token is empty.');
      }

      final roleStr = role == LiveRole.broadcaster ? 'broadcaster' : 'audience';
      final token = await _tokenService.fetchRtcToken(
        channelName: channelName,
        uid: uid,
        role: roleStr,
        authToken: idToken,
      );
      debugPrint('🔑 [Mobile] Token fetched (${token.length} chars)');
      return token;
    } catch (e) {
      debugPrint('⚠️ [Mobile] Token fetch error: $e');
      return '';
    }
  }

  @override
  Future<void> leaveChannel() async {
    if (_joined) {
      await _engine?.leaveChannel();
      _joined = false;
      isJoined.value = false;
      remoteUid.value = null;
      _tokenService.clearCache();
    }
  }

  @override
  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
    await _engine?.muteLocalAudioStream(isMuted.value);
  }

  @override
  Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
    await _engine?.muteLocalVideoStream(!isVideoEnabled.value);
  }

  @override
  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  @override
  void createLocalVideoOverlay() {
    // On mobile, video is rendered via AgoraVideoView in the widget tree.
    debugPrint('📱 [Mobile] createLocalVideoOverlay — rendered via widget tree');
  }

  @override
  void createRemoteVideoOverlay() {
    debugPrint('📱 [Mobile] createRemoteVideoOverlay — rendered via widget tree');
  }

  @override
  void removeVideoOverlay() {
    // No-op on mobile — AgoraVideoView widgets unmount with the screen.
  }

  @override
  Future<void> dispose() async {
    await leaveChannel();
    await _engine?.release();
    _engine = null;
    _initialized = false;
    isJoined.dispose();
    isMuted.dispose();
    isVideoEnabled.dispose();
    remoteUid.dispose();
  }
}
