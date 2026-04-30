import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/agora_constants.dart';

/// Agora role for token generation
enum AgoraRole { publisher, subscriber }

/// Service for managing Agora RTC engine
class AgoraService {
  RtcEngine? _engine;
  bool _initialized = false;
  
  /// Stream controllers for events
  final _localUserJoined = StreamController<bool>.broadcast();
  final _remoteUserJoined = StreamController<int>.broadcast();
  final _remoteUserLeft = StreamController<int>.broadcast();
  final _error = StreamController<String>.broadcast();
  
  /// Public streams
  Stream<bool> get localUserJoined => _localUserJoined.stream;
  Stream<int> get remoteUserJoined => _remoteUserJoined.stream;
  Stream<int> get remoteUserLeft => _remoteUserLeft.stream;
  Stream<String> get error => _error.stream;
  
  /// Get the engine instance
  RtcEngine? get engine => _engine;

  /// Initialize Agora engine
  Future<bool> initialize() async {
    if (_initialized) return true;
    
    try {
      // Request permissions first
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      
      if (cameraStatus.isDenied || micStatus.isDenied) {
        throw Exception('Camera and microphone permissions required');
      }
      
      // Create engine
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: AgoraConstants.appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      
      // Enable video and audio
      await _engine!.enableVideo();
      await _engine!.enableAudio();
      
      // Setup event handlers
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('✅ Local user joined channel: ${connection.localUid}');
          _localUserJoined.add(true);
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('👤 Remote user joined: $remoteUid');
          _remoteUserJoined.add(remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('👋 Remote user left: $remoteUid');
          _remoteUserLeft.add(remoteUid);
        },
        onError: (err, msg) {
          debugPrint('❌ Agora error: $err - $msg');
          _error.add('Error $err: $msg');
        },
      ));
      
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('Failed to initialize Agora: $e');
      return false;
    }
  }

  /// Fetch token from Supabase Edge Function
  Future<String> fetchToken({
    required String channelName,
    required int uid,
    required AgoraRole role,
  }) async {
    final response = await http.post(
      Uri.parse(AgoraConstants.tokenServerUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'channel_name': channelName,
        'uid': uid,
        'role': role.name,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch token: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['token'] as String;
  }

  /// Join channel as host (publisher)
  Future<bool> joinAsHost({
    required String channelId,
    required String token,
    required int uid,
  }) async {
    if (_engine == null) return false;
    
    try {
      await _engine!.setClientRole(
        role: ClientRoleType.clientRoleBroadcaster,
        options: const ClientRoleOptions(),
      );
      await _engine!.startPreview();
      
      await _engine!.joinChannel(
        token: token,
        channelId: channelId,
        uid: uid,
        options: const ChannelMediaOptions(
          autoSubscribeVideo: true,
          autoSubscribeAudio: true,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Failed to join as host: $e');
      return false;
    }
  }

  /// Join channel as audience (subscriber)
  Future<bool> joinAsAudience({
    required String channelId,
    required String token,
    required int uid,
  }) async {
    if (_engine == null) return false;
    
    try {
      await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
      
      await _engine!.joinChannel(
        token: token,
        channelId: channelId,
        uid: uid,
        options: const ChannelMediaOptions(
          autoSubscribeVideo: true,
          autoSubscribeAudio: true,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          clientRoleType: ClientRoleType.clientRoleAudience,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Failed to join as audience: $e');
      return false;
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  /// Mute/unmute local audio
  Future<void> muteLocalAudio(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  /// Mute/unmute local video
  Future<void> muteLocalVideo(bool muted) async {
    await _engine?.muteLocalVideoStream(muted);
  }

  /// Leave the current channel
  Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
  }

  /// Dispose the engine and release resources
  Future<void> dispose() async {
    await leaveChannel();
    await _engine?.release();
    _engine = null;
    _initialized = false;
    
    await _localUserJoined.close();
    await _remoteUserJoined.close();
    await _remoteUserLeft.close();
    await _error.close();
  }
}