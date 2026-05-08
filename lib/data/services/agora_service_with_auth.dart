import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';
import '../../app/config/app_env.dart';

class AgoraConfig {
  static String get appId => AppEnv.agoraAppId;
  static const int uid = 0;
}

enum AgoraRole { broadcaster, audience }

class AgoraService {
  static dynamic _rtcClient;
  static dynamic _localVideoTrack;
  static dynamic _localAudioTrack;
  static bool _initialized = false;
  static bool _joined = false;
  
  static final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<int?> remoteUid = ValueNotifier<int?>(null);
  
  static dynamic get engine => null;
  
  static Future<void> initialize() async {
    if (_initialized) return;
    
    print('🟢 Initializing Agora Web SDK...');
    
    for (int i = 0; i < 50; i++) {
      if (html.window.hasProperty('AgoraRTC')) {
        print('✅ AgoraRTC found');
        break;
      }
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    final AgoraRTC = html.window['AgoraRTC'];
    if (AgoraRTC == null) {
      throw Exception('AgoraRTC not loaded');
    }
    
    _rtcClient = await js_util.callMethod(AgoraRTC, 'createClient', [
      js.jsify({'mode': 'live', 'codec': 'vp8'})
    ]);
    
    _initialized = true;
    print('✅ Agora Web SDK initialized');
  }
  
  static Future<String> _fetchToken(String channelName, int uid) async {
    // Try to get Firebase token from localStorage or window
    final idToken = html.window.localStorage['firebase_id_token'];
    
    final response = await html.HttpRequest.request(
      'https://nxkutpjdoidfwpkjbwcm.supabase.co/functions/v1/agora-token?channel=$channelName&uid=$uid',
      method: 'GET',
      requestHeaders: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );
    
    if (response.status == 200) {
      final data = js_util.callMethod(html.window, 'JSON.parse', [response.responseText]);
      return js_util.getProperty(data, 'token') ?? '';
    } else {
      print('⚠️ Token fetch failed: ${response.status}');
      return ''; // Return empty token for testing
    }
  }
  
  static Future<void> joinChannel({
    required String channelName,
    required AgoraRole role,
    String? token,
    int? uid,
  }) async {
    print('🟡 Joining channel: $channelName');
    
    if (!_initialized) await initialize();
    
    final userId = uid?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Fetch token if not provided
    String finalToken = token ?? '';
    if (finalToken.isEmpty) {
      try {
        finalToken = await _fetchToken(channelName, int.parse(userId));
        print('✅ Token fetched');
      } catch (e) {
        print('⚠️ Using empty token: $e');
      }
    }
    
    try {
      await js_util.callMethod(_rtcClient, 'join', [finalToken, channelName, userId]);
      _joined = true;
      isJoined.value = true;
      print('✅ Joined channel: $channelName');
      
      if (role == AgoraRole.broadcaster) {
        final AgoraRTC = html.window['AgoraRTC'];
        
        print('🎥 Creating camera track...');
        _localVideoTrack = await js_util.callMethod(AgoraRTC, 'createCameraVideoTrack');
        print('✅ Camera ready');
        
        print('🎤 Creating microphone track...');
        _localAudioTrack = await js_util.callMethod(AgoraRTC, 'createMicrophoneAudioTrack');
        print('✅ Microphone ready');
        
        await js_util.callMethod(_rtcClient, 'publish', [_localVideoTrack]);
        await js_util.callMethod(_rtcClient, 'publish', [_localAudioTrack]);
        
        print('🎬 LIVE STREAM ACTIVE!');
      }
    } catch (e) {
      print('❌ Join failed: $e');
      rethrow;
    }
  }
  
  static Future<void> leaveChannel() async {
    if (_rtcClient != null && _joined) {
      await js_util.callMethod(_rtcClient, 'leave');
      _joined = false;
      isJoined.value = false;
      print('✅ Left channel');
    }
  }
  
  static Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
  }
  
  static Future<void> toggleVideo() async {
    isVideoEnabled.value = !isVideoEnabled.value;
  }
  
  static Future<void> switchCamera() async {
    print('📷 Camera switch - Web limitation');
  }
  
  static Future<void> dispose() async {
    await leaveChannel();
  }
}
