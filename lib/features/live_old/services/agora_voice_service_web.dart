import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

/// Voice calling service specifically for web platform.
/// Uses Agora Web SDK (AgoraRTC) for voice communication.
/// 
/// This service is designed for voice-only calls and uses the
/// Agora Voice SDK capabilities through the web JavaScript SDK.
class AgoraVoiceServiceWeb {
  static final AgoraVoiceServiceWeb _instance = AgoraVoiceServiceWeb._internal();
  
  factory AgoraVoiceServiceWeb() => _instance;
  
  AgoraVoiceServiceWeb._internal();

  dynamic _client;
  dynamic _localAudioTrack;
  String? _currentChannelId;
  bool _isJoined = false;
  
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  final StreamController<int> _remoteUserJoinedController = StreamController<int>.broadcast();
  final StreamController<int> _remoteUserLeftController = StreamController<int>.broadcast();

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;
  
  /// Stream of remote users joining the channel
  Stream<int> get onRemoteUserJoined => _remoteUserJoinedController.stream;
  
  /// Stream of remote users leaving the channel
  Stream<int> get onRemoteUserLeft => _remoteUserLeftController.stream;

  bool get isJoined => _isJoined;
  String? get currentChannelId => _currentChannelId;

  /// Initialize and join a voice channel
  /// 
  /// [appId] - The Agora App ID
  /// [channelId] - The channel to join
  /// [token] - The token for authentication (can be null for test mode)
  /// [uid] - The user ID (0 for auto-assign)
  Future<void> joinVoiceChannel({
    required String appId,
    required String channelId,
    String? token,
    int uid = 0,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('AgoraVoiceServiceWeb is only supported on web platform');
    }

    try {
      debugPrint('AgoraVoiceServiceWeb: Joining voice channel $channelId');

      // Wait for AgoraRTC to be available
      await _waitForAgoraRTC();

      // Create client with live streaming mode for voice
      _client = js.context['AgoraRTC'].callMethod('createClient', [
        js.JsObject.jsify({
          'mode': 'live',
          'codec': 'vp8',
        })
      ]);

      // Set up event handlers
      _setupEventHandlers();

      // Set client role to host (for voice broadcasting)
      await _client.callMethod('setClientRole', ['host']).toFuture();

      // Join the channel
      final jsUid = uid == 0 ? null : uid;
      await _client.callMethod('join', [
        null, // appId is obtained from token
        channelId,
        token,
        jsUid
      ]).toFuture();

      _currentChannelId = channelId;

      // Create and publish local audio track
      _localAudioTrack = await js.context['AgoraRTC'].callMethod('createMicrophoneAudioTrack').toFuture();
      await _client.callMethod('publish', [_localAudioTrack]).toFuture();

      _isJoined = true;
      _connectionStateController.add(true);

      debugPrint('AgoraVoiceServiceWeb: Successfully joined voice channel');
    } catch (e, stackTrace) {
      debugPrint('AgoraVoiceServiceWeb: Error joining voice channel: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Join as audience (listen-only mode)
  Future<void> joinAsAudience({
    required String appId,
    required String channelId,
    String? token,
    int uid = 0,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('AgoraVoiceServiceWeb is only supported on web platform');
    }

    try {
      debugPrint('AgoraVoiceServiceWeb: Joining voice channel as audience: $channelId');

      await _waitForAgoraRTC();

      _client = js.context['AgoraRTC'].callMethod('createClient', [
        js.JsObject.jsify({
          'mode': 'live',
          'codec': 'vp8',
        })
      ]);

      _setupEventHandlers();

      // Set client role to audience (listen-only)
      await _client.callMethod('setClientRole', ['audience']).toFuture();

      final jsUid = uid == 0 ? null : uid;
      await _client.callMethod('join', [
        null,
        channelId,
        token,
        jsUid
      ]).toFuture();

      _currentChannelId = channelId;
      _isJoined = true;
      _connectionStateController.add(true);

      debugPrint('AgoraVoiceServiceWeb: Successfully joined as audience');
    } catch (e, stackTrace) {
      debugPrint('AgoraVoiceServiceWeb: Error joining as audience: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _setupEventHandlers() {
    if (_client == null) return;

    // User joined handler
    _client['on']('user-published', (dynamic user, dynamic mediaType) {
      debugPrint('AgoraVoiceServiceWeb: User published: ${user['uid']}, type: $mediaType');
      // Subscribe to remote audio
      _client.callMethod('subscribe', [user, 'audio']).then((_) {
        debugPrint('AgoraVoiceServiceWeb: Subscribed to user ${user['uid']}');
      });
    });

    // User left handler
    _client['on']('user-left', (dynamic user) {
      debugPrint('AgoraVoiceServiceWeb: User left: ${user['uid']}');
      _remoteUserLeftController.add(user['uid']);
    });

    // User joined handler
    _client['on']('user-joined', (dynamic user) {
      debugPrint('AgoraVoiceServiceWeb: User joined: ${user['uid']}');
      _remoteUserJoinedController.add(user['uid']);
    });

    // Token privilege handler
    _client['on']('token-privilege-will-expire', () {
      debugPrint('AgoraVoiceServiceWeb: Token privilege will expire');
    });

    // Connection state handler
    _client['on']('connection-state-change', (dynamic state) {
      debugPrint('AgoraVoiceServiceWeb: Connection state changed: $state');
      _connectionStateController.add(state == 'CONNECTED');
    });
  }

  /// Leave the current voice channel
  Future<void> leaveChannel() async {
    if (!kIsWeb) return;

    try {
      debugPrint('AgoraVoiceServiceWeb: Leaving voice channel');

      if (_localAudioTrack != null) {
        _localAudioTrack.callMethod('close');
        _localAudioTrack = null;
      }

      if (_client != null) {
        await _client.callMethod('leave').toFuture();
        _client = null;
      }

      _isJoined = false;
      _currentChannelId = null;
      _connectionStateController.add(false);

      debugPrint('AgoraVoiceServiceWeb: Successfully left voice channel');
    } catch (e) {
      debugPrint('AgoraVoiceServiceWeb: Error leaving channel: $e');
    }
  }

  /// Mute/unmute local audio
  Future<void> toggleMute() async {
    if (_localAudioTrack == null) return;

    try {
      final isMuted = _localAudioTrack!['muted'] as bool? ?? false;
      if (isMuted) {
        await _localAudioTrack!.callMethod('setEnabled', [true]).toFuture();
        debugPrint('AgoraVoiceServiceWeb: Audio unmuted');
      } else {
        await _localAudioTrack!.callMethod('setEnabled', [false]).toFuture();
        debugPrint('AgoraVoiceServiceWeb: Audio muted');
      }
    } catch (e) {
      debugPrint('AgoraVoiceServiceWeb: Error toggling mute: $e');
    }
  }

  /// Check if local audio is muted
  bool isAudioMuted() {
    if (_localAudioTrack == null) return true;
    return _localAudioTrack!['muted'] as bool? ?? false;
  }

  /// Wait for AgoraRTC to be available in JavaScript context
  Future<void> _waitForAgoraRTC() async {
    const maxAttempts = 50;
    const delay = Duration(milliseconds: 100);
    
    for (int i = 0; i < maxAttempts; i++) {
      if (js.context['AgoraRTC'] != null) {
        return;
      }
      await Future.delayed(delay);
    }
    
    throw Exception('AgoraRTC failed to load after ${maxAttempts * delay.inMilliseconds}ms');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await leaveChannel();
    
    await _connectionStateController.close();
    await _remoteUserJoinedController.close();
    await _remoteUserLeftController.close();
  }
}