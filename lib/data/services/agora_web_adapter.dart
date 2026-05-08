import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../app/config/app_env.dart';
```


class AgoraWebAdapter {
  static dynamic _rtcClient;
  static dynamic _rtmClient;
  static dynamic _rtmChannel;
  static bool _rtcInitialized = false;
  static bool _rtmInitialized = false;
  static String _currentChannel = '';
  
  static Completer<void>? _rtcJoinCompleter;
  static Completer<void>? _rtmJoinCompleter;
  
  // Initialize RTC
  static Future<void> initRTC(String appId) async {
    if (_rtcInitialized) return;
    
    try {
      final AgoraRTC = js.context['AgoraRTC'];
      if (AgoraRTC == null) throw Exception('AgoraRTC not loaded');
      
      _rtcClient = await js_util.callMethod(AgoraRTC, 'createClient', [
        js.jsify({'mode': 'live', 'codec': 'vp8'})
      ]);
      
      _rtcInitialized = true;
      debugPrint('✅ Agora RTC initialized');
    } catch (e) {
      debugPrint('❌ Failed to init RTC: $e');
      rethrow;
    }
  }
  
  // Initialize RTM
  static Future<void> initRTM(String appId) async {
    if (_rtmInitialized) return;
    
    try {
      final AgoraRTM = js.context['AgoraRTM'];
      if (AgoraRTM == null) throw Exception('AgoraRTM not loaded');
      
      _rtmClient = await js_util.callMethod(AgoraRTM, 'createInstance', [appId]);
      _rtmInitialized = true;
      debugPrint('✅ Agora RTM initialized');
    } catch (e) {
      debugPrint('❌ Failed to init RTM: $e');
      rethrow;
    }
  }
  
  // Join RTC channel as host
  static Future<void> joinRTCAsHost(String channel, String token, String uid) async {
    final String appId = AppEnv.agoraAppId;
    if (appId.isEmpty) {
      throw Exception('Agora App ID is empty. Check AppEnv.agoraAppId configuration.');
    }
    if (!_rtcInitialized) await initRTC(appId);
    
    _rtcJoinCompleter = Completer<void>();
    _currentChannel = channel;
    
    try {
      // Agora v4 join: (appid, channel, token, uid)
      final tokenOrNull = token.isEmpty ? null : token;
      await js_util.callMethod(_rtcClient, 'join', [appId, channel, tokenOrNull, uid]);
      
      // Create and publish local tracks
      final AgoraRTC = js.context['AgoraRTC'];
      final videoTrack = await js_util.callMethod(AgoraRTC, 'createCameraVideoTrack');
      final audioTrack = await js_util.callMethod(AgoraRTC, 'createMicrophoneAudioTrack');
      
      await js_util.callMethod(_rtcClient, 'publish', [[videoTrack, audioTrack]]);
      
      debugPrint('✅ Joined RTC channel as host: $channel');
      _rtcJoinCompleter?.complete();
    } catch (e) {
      _rtcJoinCompleter?.completeError(e);
      debugPrint('❌ Failed to join RTC: $e');
      rethrow;
    }
  }
  
  // Join RTC channel as viewer
  static Future<void> joinRTCAsViewer(String channel, String token, String uid) async {
    final String appId = AppEnv.agoraAppId;
    if (appId.isEmpty) {
      throw Exception('Agora App ID is empty. Check AppEnv.agoraAppId configuration.');
    }
    if (!_rtcInitialized) await initRTC(appId);
    
    _rtcJoinCompleter = Completer<void>();
    _currentChannel = channel;
    
    try {
      // Agora v4 join: (appid, channel, token, uid)
      final tokenOrNull = token.isEmpty ? null : token;
      await js_util.callMethod(_rtcClient, 'join', [appId, channel, tokenOrNull, uid]);
      
      // Subscribe to remote users
      js_util.setProperty(_rtcClient, 'on', js_util.getProperty(_rtcClient, 'on').call([
        'user-published',
        js.JsFunction.withThis((thisArg, args) async {
          final user = args[0];
          final mediaType = args[1];
          await js_util.callMethod(_rtcClient, 'subscribe', [user, mediaType]);
          if (mediaType == 'video') {
            final videoTrack = js_util.getProperty(user, 'videoTrack');
            // Track will be played in UI
          }
        })
      ]));
      
      debugPrint('✅ Joined RTC channel as viewer: $channel');
      _rtcJoinCompleter?.complete();
    } catch (e) {
      _rtcJoinCompleter?.completeError(e);
      debugPrint('❌ Failed to join RTC: $e');
      rethrow;
    }
  }
  
  // Login to RTM
  static Future<void> loginRTM(String token, String uid) async {
    if (!_rtmInitialized) return;
    
    _rtmJoinCompleter = Completer<void>();
    
    try {
      await js_util.callMethod(_rtmClient, 'login', [js.jsify({'token': token, 'uid': uid})]);
      debugPrint('✅ RTM logged in as: $uid');
      _rtmJoinCompleter?.complete();
    } catch (e) {
      _rtmJoinCompleter?.completeError(e);
      debugPrint('❌ Failed to login RTM: $e');
      rethrow;
    }
  }
  
  // Join RTM channel
  static Future<void> joinRTMChannel(String channel) async {
    if (!_rtmInitialized) return;
    
    try {
      _rtmChannel = await js_util.callMethod(_rtmClient, 'createChannel', [channel]);
      await js_util.callMethod(_rtmChannel, 'join');
      debugPrint('✅ Joined RTM channel: $channel');
    } catch (e) {
      debugPrint('❌ Failed to join RTM channel: $e');
      rethrow;
    }
  }
  
  // Send gift via RTM
  static Future<void> sendGift(String toUser, Map<String, dynamic> gift) async {
    if (_rtmChannel == null) {
      debugPrint('❌ RTM channel not joined');
      return;
    }
    
    final message = js.jsify({
      'type': 'gift',
      'to': toUser,
      'gift': gift,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
    
    try {
      await js_util.callMethod(_rtmChannel, 'sendMessage', [js.jsify({'text': js_util.callMethod(message, 'toString', [])})]);
      debugPrint('✅ Gift sent: ${gift['name']}');
    } catch (e) {
      debugPrint('❌ Failed to send gift: $e');
    }
  }
  
  // Listen for RTM messages
  static void onRTMMessage(Function(Map<String, dynamic>) callback) {
    if (_rtmChannel == null) return;
    
    js_util.setProperty(_rtmChannel, 'on', js_util.getProperty(_rtmChannel, 'on').call([
      'ChannelMessage',
      js.JsFunction.withThis((thisArg, args) {
        final message = args[0];
        final senderId = args[1];
        final text = js_util.getProperty(message, 'text');
        try {
          final data = js_util.callMethod(js.context['JSON'], 'parse', [text]);
          callback(js_util.dartify(data));
        } catch (e) {
          debugPrint('Failed to parse message: $e');
        }
      })
    ]));
  }
  
  // Leave all channels
  static Future<void> leave() async {
    try {
      if (_rtcClient != null) {
        await js_util.callMethod(_rtcClient, 'leave');
      }
      if (_rtmChannel != null) {
        await js_util.callMethod(_rtmChannel, 'leave');
      }
      if (_rtmClient != null) {
        await js_util.callMethod(_rtmClient, 'logout');
      }
      debugPrint('✅ Left all channels');
    } catch (e) {
      debugPrint('❌ Error leaving channels: $e');
    }
  }
  
  static bool get isRTCConnected => _rtcJoinCompleter?.isCompleted ?? false;
  static bool get isRTMConnected => _rtmJoinCompleter?.isCompleted ?? false;
}
