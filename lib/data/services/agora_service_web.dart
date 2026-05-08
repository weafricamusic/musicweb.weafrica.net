import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'agora_web_adapter.dart' as web;
import '../../app/config/app_env.dart';

enum AgoraRole { broadcaster, audience }

class AgoraConfig {
  static String get appId => AppEnv.agoraAppId;
  static const int uid = 0;
}

class AgoraServiceWeb {
  bool _initialized = false;
  
  final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<int?> remoteUid = ValueNotifier<int?>(null);
  
  dynamic _mockEngine;
  
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await web.AgoraWebAdapter.initRTC(AppEnv.agoraAppId);
      await web.AgoraWebAdapter.initRTM(AppEnv.agoraAppId);
      _initialized = true;
      debugPrint('✅ Agora Web Service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Agora Web: $e');
    }
  }
  
  Future<void> joinChannel({
    required String channelName,
    required AgoraRole role,
    String? token,
    int? uid,
  }) async {
    if (!_initialized) await initialize();
    
    try {
      final isBroadcaster = role == AgoraRole.broadcaster;
      
      if (isBroadcaster) {
        await web.AgoraWebAdapter.joinRTCAsHost(
          channelName,
          token ?? '',
          uid?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString()
        );
      } else {
        await web.AgoraWebAdapter.joinRTCAsViewer(
          channelName,
          token ?? '',
          uid?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString()
        );
      }
      
      await web.AgoraWebAdapter.loginRTM(
        token ?? '',
        uid?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString()
      );
      await web.AgoraWebAdapter.joinRTMChannel(channelName);
      
      isJoined.value = true;
      debugPrint('✅ Joined web channel as ${isBroadcaster ? "broadcaster" : "audience"}');
    } catch (e) {
      debugPrint('❌ Failed to join web channel: $e');
    }
  }
  
  Future<void> leaveChannel() async {
    try {
      await web.AgoraWebAdapter.leave();
      isJoined.value = false;
      debugPrint('✅ Left web channel');
    } catch (e) {
      debugPrint('❌ Failed to leave web channel: $e');
    }
  }
  
  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
    debugPrint('🎤 Mute: ${isMuted.value}');
  }
  
  Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
    debugPrint('📹 Video: ${isVideoEnabled.value}');
  }
  
  Future<void> switchCamera() async {
    debugPrint('📷 Camera switch - web limitation');
  }
  
  Future<void> dispose() async {
    await leaveChannel();
  }
  
  dynamic get engine {
    if (_mockEngine == null) {
      _mockEngine = _MockRtcEngine();
    }
    return _mockEngine;
  }
}

class _MockRtcEngine {
  @override
  String toString() => 'MockRtcEngine (Web Only)';
}
