import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

class AgoraServiceWeb {
  static dynamic _client;
  static dynamic _localVideoTrack;
  static dynamic _localAudioTrack;
  static bool _initialized = false;
  static bool _joined = false;
  
  static final ValueNotifier<bool> isJoined = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isVideoEnabled = ValueNotifier<bool>(true);
  
  static Future<void> initialize(String appId) async {
    if (_initialized) return;
    
    debugPrint('🔵 Waiting for Agora SDK...');
    
    // Wait for the promise from index.html
    final completer = Completer();
    if (html.window.hasProperty('agoraReadyPromise')) {
      final promise = html.window['agoraReadyPromise'];
      promise.then((_) {
        debugPrint('✅ Agora promise resolved');
        completer.complete();
      }).catchError((e) {
        debugPrint('❌ Agora promise rejected: $e');
        completer.completeError(e);
      });
    } else {
      debugPrint('⚠️ No agoraReadyPromise found, checking directly');
      completer.complete();
    }
    
    await completer.future.timeout(
      Duration(seconds: 10),
      onTimeout: () => debugPrint('⚠️ Timeout waiting for Agora'),
    );
    
    final AgoraRTC = html.window['AgoraRTC'] ?? html.window['agoraRTC'];
    if (AgoraRTC == null) {
      throw Exception('AgoraRTC not available');
    }
    
    debugPrint('✅ AgoraRTC version: ${js_util.getProperty(AgoraRTC, 'VERSION')}');
    
    _client = await js_util.callMethod(AgoraRTC, 'createClient', [
      js.jsify({'mode': 'live', 'codec': 'vp8'})
    ]);
    
    _initialized = true;
    debugPrint('✅ Agora Web client created');
  }
  
  static Future<void> joinAsHost(String channelName, String token, String uid) async {
    if (!_initialized) await initialize('');
    
    try {
      await js_util.callMethod(_client, 'join', [token, channelName, uid]);
      debugPrint('✅ Joined channel: $channelName');
      
      final AgoraRTC = html.window['AgoraRTC'];
      
      _localVideoTrack = await js_util.callMethod(AgoraRTC, 'createCameraVideoTrack');
      _localAudioTrack = await js_util.callMethod(AgoraRTC, 'createMicrophoneAudioTrack');
      
      await js_util.callMethod(_client, 'publish', [_localVideoTrack]);
      await js_util.callMethod(_client, 'publish', [_localAudioTrack]);
      
      _joined = true;
      isJoined.value = true;
      debugPrint('✅ Publishing video and audio');
    } catch (e) {
      debugPrint('❌ Join failed: $e');
      rethrow;
    }
  }
  
  static Future<void> leave() async {
    if (_client != null && _joined) {
      await js_util.callMethod(_client, 'leave');
      _joined = false;
      isJoined.value = false;
    }
  }
  
  static void toggleMute() => isMuted.value = !isMuted.value;
  static void toggleVideo() => isVideoEnabled.value = !isVideoEnabled.value;
  static void switchCamera() => debugPrint('📷 Switch camera');
}

class Completer<T> {
  Completer() {
    _completer = CompleterImpl<T>();
  }
  late CompleterImpl<T> _completer;
  Future<T> get future => _completer.future;
  void complete([T? value]) => _completer.complete(value);
  void completeError(Object error) => _completer.completeError(error);
}

class CompleterImpl<T> {
  final _completer = Completer<T>();
  Future<T> get future => _completer.future;
  void complete([T? value]) => _completer.complete(value);
  void completeError(Object error) => _completer.completeError(error);
}
