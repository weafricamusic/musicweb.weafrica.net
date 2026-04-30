import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to manage Agora RTC (Real-Time Communication) for live streaming.
class AgoraRtcService {
  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _localVideoMuted = false;
  bool _localAudioMuted = false;
  
  String? _currentChannelId;
  String? _currentUserId;
  int? _dataStreamId;

  // Stream controllers for events
  final _userJoinedController = StreamController<int>.broadcast();
  final _userLeftController = StreamController<int>.broadcast();
  final _giftReceivedController = StreamController<GiftData>.broadcast();

  // Public streams
  Stream<int> get onUserJoined => _userJoinedController.stream;
  Stream<int> get onUserLeft => _userLeftController.stream;
  Stream<GiftData> get onGiftReceived => _giftReceivedController.stream;

  /// Initialize the Agora engine.
  Future<void> initialize({
    required String appId,
    required bool isHost,
    required String channelId,
    required String token,
    required String userId,
  }) async {
    if (_isInitialized) return;

    _currentChannelId = channelId;
    _currentUserId = userId;

    // Request permissions
    await [Permission.camera, Permission.microphone].request();

    // Create engine
    _engine = createAgoraRtcEngine();
    
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    // Set client role
    await _engine!.setClientRole(
      role: isHost 
          ? ClientRoleType.clientRoleBroadcaster 
          : ClientRoleType.clientRoleAudience,
    );

    // Register event handlers
    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('Joined channel: ${connection.channelId}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('User joined: $remoteUid');
        _userJoinedController.add(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('User left: $remoteUid');
        _userLeftController.add(remoteUid);
      },
      onStreamMessage: (connection, remoteUid, streamId, data, length, sentTs) {
        // Handle incoming stream messages (gifts, etc.)
        _handleStreamMessage(data, remoteUid);
      },
    ));

    // Join channel
    await _engine!.joinChannel(
      token: token,
      channelId: channelId,
      uid: int.tryParse(userId) ?? 0,
      options: const ChannelMediaOptions(),
    );

    // Create data stream for sending messages (gifts)
    _dataStreamId = await _engine!.createDataStream(
      const DataStreamConfig(syncWithAudio: false, ordered: false),
    );

    if (isHost) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    _isInitialized = true;
  }

  /// Handle incoming stream messages (like gifts).
  void _handleStreamMessage(Uint8List data, int remoteUid) {
    try {
      final jsonString = utf8.decode(data);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      if (jsonData['type'] == 'gift') {
        final giftData = GiftData.fromJson(jsonData);
        _giftReceivedController.add(giftData);
      }
    } catch (e) {
      debugPrint('Error handling stream message: $e');
    }
  }

  /// Toggle local video.
  Future<void> toggleLocalVideo() async {
    if (_engine == null) return;
    
    _localVideoMuted = !_localVideoMuted;
    // Agora 6.x uses positional bool parameter
    await _engine!.muteLocalVideoStream(_localVideoMuted);
  }

  /// Toggle local audio.
  Future<void> toggleLocalAudio() async {
    if (_engine == null) return;
    
    _localAudioMuted = !_localAudioMuted;
    // Agora 6.x uses positional bool parameter
    await _engine!.muteLocalAudioStream(_localAudioMuted);
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    if (_engine == null) return;
    await _engine!.switchCamera();
  }

  /// Send a gift message to the channel.
  /// 
  /// [channelId] - The channel ID where the gift is sent
  /// [senderName] - Display name of the sender
  /// [senderId] - User ID of the sender
  /// [toHostId] - User ID of the host receiving the gift
  /// [giftType] - Type of gift (e.g., 'rose', 'diamond', 'crown')
  /// [quantity] - Number of gifts
  /// [totalCoins] - Total coin value
  Future<void> sendGift({
    required String channelId,
    required String senderName,
    required String senderId,
    required String toHostId,
    required String giftType,
    required int quantity,
    required int totalCoins,
  }) async {
    if (_engine == null || _dataStreamId == null) return;

    final giftData = GiftData(
      senderName: senderName,
      senderId: senderId,
      toHostId: toHostId,
      giftType: giftType,
      quantity: quantity,
      totalCoins: totalCoins,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final jsonData = jsonEncode({
      'type': 'gift',
      ...giftData.toJson(),
    });

    final data = Uint8List.fromList(utf8.encode(jsonData));
    
    // Send as stream message using Agora 6.x API
    await _engine!.sendStreamMessage(
      streamId: _dataStreamId!,
      data: data,
      length: data.length,
    );
  }

  /// Leave the current channel.
  Future<void> leaveChannel() async {
    if (_engine == null) return;
    
    await _engine!.leaveChannel();
    await _engine!.stopPreview();
  }

  /// Dispose the engine and cleanup.
  Future<void> dispose() async {
    await leaveChannel();
    await _engine?.release();
    _engine = null;
    _isInitialized = false;
    
    await _userJoinedController.close();
    await _userLeftController.close();
    await _giftReceivedController.close();
  }

  /// Get local video preview widget.
  Widget get localVideoPreview {
    if (_engine == null) return const SizedBox.shrink();
    
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  /// Get remote video view for a specific user.
  Widget getRemoteVideo(int uid) {
    if (_engine == null) return const SizedBox.shrink();
    
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: _currentChannelId ?? ''),
      ),
    );
  }

  bool get isInitialized => _isInitialized;
  bool get isLocalVideoMuted => _localVideoMuted;
  bool get isLocalAudioMuted => _localAudioMuted;
}

/// Data class representing a gift.
class GiftData {
  final String senderName;
  final String senderId;
  final String toHostId;
  final String giftType;
  final int quantity;
  final int totalCoins;
  final int timestamp;

  GiftData({
    required this.senderName,
    required this.senderId,
    required this.toHostId,
    required this.giftType,
    required this.quantity,
    required this.totalCoins,
    required this.timestamp,
  });

  factory GiftData.fromJson(Map<String, dynamic> json) {
    return GiftData(
      senderName: json['senderName'] as String,
      senderId: json['senderId'] as String,
      toHostId: json['toHostId'] as String,
      giftType: json['giftType'] as String,
      quantity: json['quantity'] as int,
      totalCoins: json['totalCoins'] as int,
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senderName': senderName,
      'senderId': senderId,
      'toHostId': toHostId,
      'giftType': giftType,
      'quantity': quantity,
      'totalCoins': totalCoins,
      'timestamp': timestamp,
    };
  }
}
