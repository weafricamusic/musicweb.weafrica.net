import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../live_engine_interface.dart';
import '../../core/enums/live_role.dart';
import '../../../../app/config/app_env.dart';
import '../../../../data/services/agora_token_service.dart';

/// Web-only engine using Agora Web SDK via JS interop.
class AgoraWebEngine implements LiveEngineInterface {
  dynamic _rtcClient;
  dynamic _localVideoTrack;
  dynamic _localAudioTrack;
  dynamic _remoteVideoTrack;
  dynamic _remoteAudioTrack;
  bool _initialized = false;
  bool _joined = false;
  bool _isBroadcaster = false;

  // DOM overlay elements
  html.DivElement? _videoContainer;
  html.DivElement? _videoDiv;
  String _videoDivId = '';
  bool _isLocalOverlay = false;

  final _tokenService = AgoraTokenService();

  @override
  dynamic get engine => _rtcClient;

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
    debugPrint('🟢 [Web] Initializing Agora Web SDK...');

    // Validate App ID BEFORE any SDK operation
    AppEnv.validateAgoraAppId();

    // Wait for AgoraRTC to be available (loaded via script tag in index.html)
    for (int i = 0; i < 50; i++) {
      if (js_util.hasProperty(html.window, 'AgoraRTC')) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final AgoraRTC = js_util.getProperty(html.window, 'AgoraRTC');
    if (AgoraRTC == null) {
      throw Exception('AgoraRTC not loaded — check index.html script tag');
    }

    _rtcClient = await js_util.callMethod(AgoraRTC, 'createClient', [
      js_util.jsify({'mode': 'live', 'codec': 'vp8'}),
    ]);

    _initialized = true;
    debugPrint('✅ [Web] Agora Web SDK initialized');
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
    final int userId = uid ?? 0;

    final String appId = AppEnv.agoraAppId;
    if (appId.isEmpty) {
      throw Exception('Agora App ID is empty. Check AppEnv.agoraAppId configuration.');
    }
    debugPrint('📋 [Web] App ID: ${appId.substring(0, 4)}... (length: ${appId.length})');

    // Fetch token from backend if not provided
    String finalToken = token ?? '';
    if (finalToken.isEmpty) {
      finalToken = await _fetchToken(channelName, userId, role);
    }
    final tokenOrNull = finalToken.isEmpty ? null : finalToken;

    try {
      await js_util.callMethod(_rtcClient, 'join', [appId, channelName, tokenOrNull, userId]);
      _joined = true;
      debugPrint('✅ [Web] Joined channel: $channelName');

      // Set client role AFTER joining, BEFORE publishing (SDK v4 requirement)
      final clientRole = _isBroadcaster ? 'host' : 'audience';
      debugPrint('🎭 [Web] Setting client role: $clientRole');
      await js_util.callMethod(_rtcClient, 'setClientRole', [clientRole]);

      if (_isBroadcaster) {
        final AgoraRTC = js_util.getProperty(html.window, 'AgoraRTC');

        debugPrint('🎥 [Web] Creating camera track...');
        _localVideoTrack = await js_util.callMethod(AgoraRTC, 'createCameraVideoTrack', []);
        _localAudioTrack = await js_util.callMethod(AgoraRTC, 'createMicrophoneAudioTrack', []);

        debugPrint('📡 [Web] Publishing tracks...');
        await js_util.callMethod(_rtcClient, 'publish', [
          js_util.jsify([_localVideoTrack, _localAudioTrack]),
        ]);
        debugPrint('🎬 [Web] LIVE STREAM ACTIVE!');
      } else {
        _setupRemoteTrackListener();
      }

      isJoined.value = true;
    } catch (e) {
      debugPrint('❌ [Web] Join failed: $e');
      _joined = false;
      isJoined.value = false;
      rethrow;
    }
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
      debugPrint('🔑 [Web] Token fetched (${token.length} chars)');
      return token;
    } catch (e) {
      debugPrint('⚠️ [Web] Token fetch error: $e');
      return '';
    }
  }

  void _setupRemoteTrackListener() {
    debugPrint('👂 [Web] Setting up remote track listener...');
    try {
      final onUserPublished = js.allowInterop((dynamic user, String mediaType) {
        final uid = js_util.getProperty(user, 'uid') as int;
        _subscribeRemoteTrack(user, mediaType, uid);
      });
      js_util.callMethod(_rtcClient, 'on', ['user-published', onUserPublished]);
    } catch (e) {
      debugPrint('❌ [Web] Failed to set up remote listener: $e');
    }
  }

  void _subscribeRemoteTrack(dynamic user, String mediaType, int uid) async {
    try {
      await js_util.callMethod(_rtcClient, 'subscribe', [user, mediaType]);
      if (mediaType == 'video') {
        _remoteVideoTrack = js_util.getProperty(user, 'videoTrack');
        remoteUid.value = uid;
        debugPrint('📹 [Web] Remote video track received for uid=$uid');
      } else if (mediaType == 'audio') {
        _remoteAudioTrack = js_util.getProperty(user, 'audioTrack');
      }
    } catch (e) {
      debugPrint('❌ [Web] Subscribe failed: $e');
    }
  }

  @override
  Future<void> leaveChannel() async {
    if (_rtcClient != null && _joined) {
      try {
        final stopFn = js_util.getProperty(html.window, '_agoraStopTrack');
        if (_localVideoTrack != null && stopFn != null) {
          js_util.callMethod(stopFn, 'call', [null, _localVideoTrack]);
        }
        if (_localAudioTrack != null && stopFn != null) {
          js_util.callMethod(stopFn, 'call', [null, _localAudioTrack]);
        }
        await js_util.callMethod(_rtcClient, 'leave', []);
      } catch (e) {
        debugPrint('❌ [Web] Leave error: $e');
      }
      _joined = false;
      _remoteVideoTrack = null;
      _remoteAudioTrack = null;
      remoteUid.value = null;
      isJoined.value = false;
      _tokenService.clearCache();
      debugPrint('✅ [Web] Left channel');
    }
  }

  @override
  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
    if (_localAudioTrack != null) {
      await js_util.callMethod(_localAudioTrack, 'setEnabled', [!isMuted.value]);
    }
    debugPrint('🎤 [Web] Mute: ${isMuted.value}');
  }

  @override
  Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
    if (_localVideoTrack != null) {
      await js_util.callMethod(_localVideoTrack, 'setEnabled', [isVideoEnabled.value]);
    }
  }

  @override
  Future<void> switchCamera() async {
    debugPrint('📷 [Web] Camera switch — limited on Web');
  }

  // ─── DOM Overlay (Web) ──────────────────────────────────

  void _playTrackInElement(dynamic track, String elementId) {
    if (track == null) return;
    try {
      final playFn = js_util.getProperty(html.window, '_agoraPlayTrack');
      if (playFn != null) {
        js_util.callMethod(playFn, 'call', [null, track, elementId]);
      } else {
        final el = html.document.getElementById(elementId);
        if (el != null) js_util.callMethod(track, 'play', [el]);
      }
      debugPrint('✅ [Web] Track playing in: $elementId');
    } catch (e) {
      debugPrint('❌ [Web] Failed to attach video: $e');
    }
  }

  void _createDomOverlay(dynamic track) {
    if (track == null) return;
    try {
      _videoDivId = 'agora-video-${DateTime.now().millisecondsSinceEpoch}';

      _videoContainer = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.zIndex = '9999'
        ..style.backgroundColor = '#000000';

      _videoDiv = html.DivElement()
        ..id = _videoDivId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      _videoContainer!.append(_videoDiv!);

      final glassPane = html.document.querySelector('flt-glass-pane');
      if (glassPane != null) {
        glassPane.append(_videoContainer!);
      } else {
        html.document.body?.append(_videoContainer!);
      }

      _playTrackInElement(track, _videoDivId);
      debugPrint('✅ [Web] DOM overlay created: $_videoDivId');
    } catch (e) {
      debugPrint('❌ [Web] DOM overlay error: $e');
    }
  }

  @override
  void createLocalVideoOverlay() {
    _isLocalOverlay = true;
    if (_localVideoTrack != null) {
      _createDomOverlay(_localVideoTrack);
    } else {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_localVideoTrack != null) _createDomOverlay(_localVideoTrack);
      });
    }
  }

  @override
  void createRemoteVideoOverlay() {
    _isLocalOverlay = false;
    if (_remoteVideoTrack != null) {
      _createDomOverlay(_remoteVideoTrack);
    }
  }

  @override
  void removeVideoOverlay() {
    _videoContainer?.remove();
    _videoContainer = null;
    _videoDiv = null;
  }

  @override
  Future<void> dispose() async {
    removeVideoOverlay();
    await leaveChannel();
    isJoined.dispose();
    isMuted.dispose();
    isVideoEnabled.dispose();
    remoteUid.dispose();
  }
}
