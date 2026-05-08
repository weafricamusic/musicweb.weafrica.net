import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';
import 'package:weafrica_music/features/live/engine/web/agora_web_video_registry.dart';
import '../../app/config/app_env.dart';
import 'agora_service_shared.dart';

/// Helper: converts a JS Promise to a Dart Future.
/// Only wraps in promiseToFuture if the value actually has a .then method.
/// Some Agora SDK methods return void/null (e.g. client.on()).
Future<T> _awaitJsPromise<T>(dynamic jsValue) {
  if (jsValue == null) {
    return Future<T>.value(null as T);
  }
  if (!js_util.hasProperty(jsValue, 'then')) {
    // Not a Promise – return the value as-is (e.g. void methods)
    return Future<T>.value(jsValue as T);
  }
  return js_util.promiseToFuture<T>(jsValue);
}

class AgoraService {
  dynamic _rtcClient;
  dynamic _localVideoTrack;
  dynamic _localAudioTrack;
  dynamic _remoteVideoTrack;
  dynamic _remoteAudioTrack;
  bool _initialized = false;
  bool _joined = false;
  bool _isBroadcaster = false;

  final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<int?> remoteUid = ValueNotifier<int?>(null);

  dynamic get engine => _rtcClient;
  dynamic get localVideoTrack => _localVideoTrack;
  dynamic get remoteVideoTrack => _remoteVideoTrack;
  bool get isBroadcaster => _isBroadcaster;

  // ─── Init ───────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    // Prevent concurrent initialization
    if (_initializing) return;
    _initializing = true;

    try {
      debugPrint('🟢 Initializing Agora Web SDK...');

      // Validate App ID before any SDK operation
      final appId = AppEnv.agoraAppId;
      if (appId.isEmpty) {
        throw Exception('Agora App ID is empty. Check AppEnv.agoraAppId configuration.');
      }
      debugPrint('📋 App ID validated: ${appId.substring(0, 4)}... (length: ${appId.length})');

      // Wait for AgoraRTC to be available (loaded via script tag in index.html)
      for (int i = 0; i < 50; i++) {
        if (js_util.hasProperty(html.window, 'AgoraRTC')) {
          debugPrint('✅ AgoraRTC found after ${i * 100}ms');
          break;
        }
        if (i == 49) {
          debugPrint('⚠️ AgoraRTC still not loaded after 5s — check index.html CDN script');
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final AgoraRTC = js_util.getProperty(html.window, 'AgoraRTC');
      if (AgoraRTC == null) {
        throw Exception('AgoraRTC not loaded — check index.html CDN script tag');
      }

      final createPromise = js_util.callMethod(AgoraRTC, 'createClient', [
        js_util.jsify({'mode': 'live', 'codec': 'vp8'}),
      ]);
      _rtcClient = await _awaitJsPromise(createPromise);

      if (_rtcClient == null) {
        throw Exception('AgoraRTC.createClient returned null');
      }

      _initialized = true;
      debugPrint('✅ Agora Web SDK initialized');
    } catch (e) {
      debugPrint('❌ Agora initialization failed: $e');
      _initializing = false;
      rethrow;
    } finally {
      _initializing = true; // mark as attempted — initialize() can be called again if needed
      if (!_initialized) _initializing = false;
    }
  }
  bool _initializing = false;

  // ─── Token ──────────────────────────────────────────────

  Future<String> _fetchToken(String channelName, int uid) async {
    // Retry up to 2 times with 1s backoff
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri =
            '${AppEnv.supabaseUrl}/functions/v1/agora-token?channel=$channelName&uid=$uid';
        final response = await html.HttpRequest.request(
          uri,
          method: 'GET',
          requestHeaders: {
            'apikey': AppEnv.supabaseAnonKey,
            'Authorization': 'Bearer ${AppEnv.supabaseAnonKey}',
          },
        );
        if (response.status == 200) {
          final decoded = jsonDecode(response.responseText ?? '{}');
          final token = decoded['token'] ?? '';
          if (token.isNotEmpty) {
            debugPrint('🔑 Agora token fetched (${token.length} chars)');
            return token;
          }
          debugPrint('⚠️ Token fetch returned empty token');
        } else {
          debugPrint('⚠️ Token fetch HTTP ${response.status}: ${response.responseText}');
        }
      } catch (e) {
        debugPrint('⚠️ Token fetch error (attempt $attempt): $e');
      }
      if (attempt < 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    debugPrint('❌ Token fetch failed after 2 attempts');
    return '';
  }

  // ─── Join Channel ───────────────────────────────────────

  Future<void> joinChannel({
    required String channelName,
    required AgoraRole role,
    String? token,
    int? uid,
  }) async {
    print('🟡 Joining channel: $channelName');

    if (!_initialized) await initialize();

    _isBroadcaster = (role == AgoraRole.broadcaster);
    // Agora Web SDK: uid=0 means auto-assign by server
    final int userId = uid ?? 0;

    final String appId = AppEnv.agoraAppId;
    if (appId.isEmpty) {
      throw Exception('Agora App ID is empty. Check AppEnv.agoraAppId configuration.');
    }
    print('📋 App ID: ${appId.substring(0, 8)}... (length: ${appId.length})');

    String finalToken = token ?? '';
    if (finalToken.isEmpty) {
      finalToken = await _fetchToken(channelName, userId);
    }

    // IMPORTANT: Agora v4.x requires a valid token for production apps.
    // Passing null triggers deprecated "static key" authentication which is no longer supported.
    // If we still don't have a token, throw an explicit error rather than
    // letting the SDK fail with the confusing "dynamic use static key" message.
    if (finalToken.isEmpty) {
      throw Exception(
        'Agora token is missing. Ensure the backend token server is reachable '
        'and CORS is configured correctly. Backend URLs:\n'
        '  - ${AppEnv.agoraTokenServerUrl.isNotEmpty ? AppEnv.agoraTokenServerUrl : 'https://weafrica-backend.vercel.app/api/agora/tokens/rtc'}\n'
        '  - ${AppEnv.supabaseUrl}/functions/v1/agora-token',
      );
    }

    try {
      // Agora v4 join: (appid, channel, token, uid)
      print('🔄 Calling client.join(appid, "$channelName", token (${finalToken.length} chars), $userId)');
      final joinPromise = js_util.callMethod(
        _rtcClient, 'join', [appId, channelName, finalToken, userId],
      );
      await _awaitJsPromise(joinPromise);
      _joined = true;
      print('✅ Joined channel: $channelName');

      if (_isBroadcaster) {
        // Set client role to host BEFORE creating/publishing tracks (SDK v4 requirement)
        print('🎭 Setting client role: host');
        final rolePromise = js_util.callMethod(_rtcClient, 'setClientRole', ['host']);
        await _awaitJsPromise(rolePromise);
        print('✅ Client role set to host');

        final AgoraRTC = js_util.getProperty(html.window, 'AgoraRTC');

        print('🎥 Creating camera track...');
        final camPromise = js_util.callMethod(AgoraRTC, 'createCameraVideoTrack', []);
        _localVideoTrack = await _awaitJsPromise(camPromise);
        print('✅ Camera track created');

        print('🎤 Creating microphone track...');
        final micPromise = js_util.callMethod(AgoraRTC, 'createMicrophoneAudioTrack', []);
        _localAudioTrack = await _awaitJsPromise(micPromise);
        print('✅ Microphone track created');

        print('📡 Publishing video...');
        final pubVideoPromise = js_util.callMethod(
          _rtcClient, 'publish', [js_util.jsify([_localVideoTrack])],
        );
        await _awaitJsPromise(pubVideoPromise);
        print('✅ Video published');

        print('📡 Publishing audio...');
        final pubAudioPromise = js_util.callMethod(
          _rtcClient, 'publish', [js_util.jsify([_localAudioTrack])],
        );
        await _awaitJsPromise(pubAudioPromise);
        print('✅ Audio published');

        print('🎬 LIVE STREAM ACTIVE!');
      } else {
        // Audience: listen for remote user-published events
        _setupRemoteTrackListener();
      }

      isJoined.value = true;
    } catch (e) {
      print('❌ Join failed: $e');
      _joined = false;
      isJoined.value = false;
      rethrow;
    }
  }

  // ─── Remote track subscription (for audience) ────────────

  void _setupRemoteTrackListener() {
    print('👂 Setting up remote track listener...');
    try {
      final onUserPublished = js.allowInterop((dynamic user, String mediaType) {
        print('📥 user-published: uid=${js_util.getProperty(user, 'uid')}, type=$mediaType');
        final uid = js_util.getProperty(user, 'uid');
        _subscribeRemoteTrack(user, mediaType, uid);
      });

      js_util.callMethod(_rtcClient, 'on', ['user-published', onUserPublished]);
      print('✅ Remote track listener active');
    } catch (e) {
      print('❌ Failed to set up remote track listener: $e');
    }
  }

  void _subscribeRemoteTrack(dynamic user, String mediaType, int uid) async {
    print('📡 Subscribing to remote $mediaType from uid=$uid');
    try {
      final subPromise = js_util.callMethod(_rtcClient, 'subscribe', [user, mediaType]);
      await _awaitJsPromise(subPromise);
      print('✅ Subscribed to $mediaType from uid=$uid');

      if (mediaType == 'video') {
        _remoteVideoTrack = js_util.getProperty(user, 'videoTrack');
        remoteUid.value = uid;
        print('📹 Remote video track received for uid=$uid');
      } else if (mediaType == 'audio') {
        _remoteAudioTrack = js_util.getProperty(user, 'audioTrack');
        print('🎤 Remote audio track received for uid=$uid');
      }
    } catch (e) {
      print('❌ Failed to subscribe remote track: $e');
    }
  }

  // ─── Leave Channel ──────────────────────────────────────

  Future<void> leaveChannel() async {
    if (_rtcClient != null && _joined) {
      try {
        final stopFn = js_util.getProperty(html.window, '_agoraStopTrack');
        if (_localVideoTrack != null) {
          try {
            if (stopFn != null) {
              js_util.callMethod(stopFn, 'call', [null, _localVideoTrack]);
            } else {
              await _awaitJsPromise(js_util.callMethod(_localVideoTrack, 'stop', []));
            }
          } catch (e) {
            print('⚠️ Could not stop video track: $e');
          }
        }
        if (_localAudioTrack != null) {
          try {
            if (stopFn != null) {
              js_util.callMethod(stopFn, 'call', [null, _localAudioTrack]);
            } else {
              await _awaitJsPromise(js_util.callMethod(_localAudioTrack, 'stop', []));
            }
          } catch (e) {
            print('⚠️ Could not stop audio track: $e');
          }
        }
        final leavePromise = js_util.callMethod(_rtcClient, 'leave', []);
        await _awaitJsPromise(leavePromise);
        _joined = false;
        _remoteVideoTrack = null;
        _remoteAudioTrack = null;
        remoteUid.value = null;
        isJoined.value = false;
        print('✅ Left channel');
      } catch (e) {
        print('❌ Error leaving channel: $e');
        _joined = false;
        isJoined.value = false;
      }
    }
  }

  // ─── Controls ───────────────────────────────────────────

  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
    if (_localAudioTrack != null) {
      await _awaitJsPromise(
        js_util.callMethod(_localAudioTrack, 'setEnabled', [!isMuted.value]),
      );
    }
    print('🎤 Mute: ${isMuted.value}');
  }

  Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
    if (_localVideoTrack != null) {
      await _awaitJsPromise(
        js_util.callMethod(_localVideoTrack, 'setEnabled', [isVideoEnabled.value]),
      );
    }
    print('📹 Video: ${isVideoEnabled.value}');
  }

  Future<void> switchCamera() async {
    print('📷 Camera switch - Web limitation');
  }

  // ─── Play track into an HtmlElementView-backed div ──────

  void _playTrackInElement(dynamic track, String key) {
    if (track == null) {
      print('⚠️ Track not available (key=$key)');
      return;
    }
    // Ensure the view is registered so the div exists.
    AgoraWebVideoRegistry.register(key);
    final element = AgoraWebVideoRegistry.getElement(key);
    if (element == null) {
      print('❌ Registry element not found for key=$key');
      return;
    }
    try {
      final playFn = js_util.getProperty(html.window, '_agoraPlayTrack');
      if (playFn != null) {
        js_util.callMethod(playFn, 'call', [null, track, element]);
      } else {
        js_util.callMethod(track, 'play', [element]);
      }
      print('✅ Track playing in HtmlElementView: $key');
    } catch (e) {
      print('❌ Failed to play track into $key: $e');
    }
  }

  // ─── Video Overlay (HtmlElementView-based) ──────────────

  /// Plays the local camera track into the `'local'` [HtmlElementView].
  void createVideoOverlay() {
    print('🎥 createVideoOverlay (local)');
    if (_localVideoTrack != null && js_util.hasProperty(_localVideoTrack, 'play')) {
      _playTrackInElement(_localVideoTrack, 'local');
    } else {
      print('⚠️ Local video track not ready — retrying in 500ms');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_localVideoTrack != null && js_util.hasProperty(_localVideoTrack, 'play')) {
          _playTrackInElement(_localVideoTrack, 'local');
        }
      });
    }
  }

  /// Plays a remote track into the `'remote-<uid>'` [HtmlElementView].
  void createRemoteVideoOverlay() {
    final uid = remoteUid.value;
    print('📹 createRemoteVideoOverlay (uid=$uid)');
    if (uid != null && _remoteVideoTrack != null) {
      _playTrackInElement(_remoteVideoTrack, 'remote-$uid');
    } else {
      print('⚠️ Remote video track not ready (uid=$uid, track=${_remoteVideoTrack != null})');
    }
  }

  void removeVideoOverlay() {
    // Tracks are stopped in leaveChannel().  HtmlElementView divs are owned
    // by Flutter and removed automatically when the widget unmounts.
    print('✅ Video overlays cleared');
  }

  Future<void> dispose() async {
    removeVideoOverlay();
    await leaveChannel();
    isJoined.dispose();
    isMuted.dispose();
    isVideoEnabled.dispose();
    remoteUid.dispose();
  }
}