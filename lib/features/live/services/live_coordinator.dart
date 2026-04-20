import 'dart:async';
import 'package:flutter/material.dart';
import 'agora_rtc_service.dart';
import '../models/live_models.dart';
import '../models/live_args.dart';

/// Coordinates Agora RTC, RTM chat, and business logic for a live stream or battle.
class LiveCoordinator extends ChangeNotifier {
  final AgoraRtcService _rtc;

  bool _isHost = false;
  String? _channelId;
  String? _userId;
  String? _userName;
  LiveStream? _currentStream;
  LiveBattle? _currentBattle;

  // Public getters
  bool get isHost => _isHost;
  String? get channelId => _channelId;
  String? get userId => _userId;
  String? get userName => _userName;
  LiveStream? get currentStream => _currentStream;
  LiveBattle? get currentBattle => _currentBattle;

  LiveCoordinator({
    required AgoraRtcService rtcService,
  })  : _rtc = rtcService;

  /// Initialize with arguments (from navigation).
  Future<void> init(LiveArgs args) async {
    _isHost = args.isHost;
    _channelId = args.channelId;
    _userId = args.userId;
    _userName = args.userName;

    // Initialize RTC
    await _rtc.initialize(
      appId: args.agoraAppId,
      isHost: args.isHost,
      channelId: args.channelId,
      token: args.agoraToken,
      userId: args.userId,
    );

    notifyListeners();
  }

  /// Dispose all resources.
  @override
  void dispose() {
    _rtc.dispose();
    super.dispose();
  }

  /// Toggle local video mute.
  Future<void> toggleVideo() async {
    await _rtc.toggleLocalVideo();
    notifyListeners();
  }

  /// Toggle local audio mute.
  Future<void> toggleAudio() async {
    await _rtc.toggleLocalAudio();
    notifyListeners();
  }

  /// Switch camera (front/back).
  Future<void> switchCamera() async {
    await _rtc.switchCamera();
  }

  /// End the stream/battle and cleanup.
  Future<void> endStream() async {
    await _rtc.leaveChannel();
  }

  /// Send a gift to the host.
  /// 
  /// [giftType] - The type of gift (e.g., 'rose', 'diamond', 'crown')
  /// [quantity] - Number of gifts to send
  /// [recipientHostId] - The user ID of the host receiving the gift
  Future<void> sendGift({
    required String giftType,
    required int quantity,
    required String recipientHostId,
  }) async {
    if (_channelId == null || _userId == null || _userName == null) {
      throw Exception('LiveCoordinator not initialized. Call init() first.');
    }

    // Calculate total coins based on gift type and quantity
    final int coinsPerGift = _getCoinsForGift(giftType);
    final int totalCoins = coinsPerGift * quantity;

    await _rtc.sendGift(
      channelId: _channelId!,
      senderName: _userName!,
      senderId: _userId!,
      toHostId: recipientHostId,
      giftType: giftType,
      quantity: quantity,
      totalCoins: totalCoins,
    );
  }

  /// Get the coin cost for a specific gift type.
  int _getCoinsForGift(String giftType) {
    switch (giftType) {
      case 'rose':
        return 1;
      case 'heart':
        return 5;
      case 'diamond':
        return 10;
      case 'crown':
        return 50;
      case 'super_car':
        return 100;
      case 'yacht':
        return 500;
      default:
        return 1;
    }
  }

  /// Get local video preview widget.
  Widget get localVideoPreview => _rtc.localVideoPreview;

  /// Get remote video view for a specific user.
  Widget getRemoteVideo(int uid) => _rtc.getRemoteVideo(uid);
}
