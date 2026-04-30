import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/config/app_env.dart';
import '../services/agora_token_api.dart';
import '../models/gift_model.dart';
import '../widgets/gift/gift_selection_sheet.dart';
import '../widgets/challenge_button.dart';

class LiveWatchScreen extends StatefulWidget {
  final String channelId;
  final String hostName;
  final String? streamId;
  final String? hostId;
  final String? title;

  const LiveWatchScreen({
    super.key,
    required this.channelId,
    required this.hostName,
    this.streamId,
    this.hostId,
    this.title,
  });

  @override
  State<LiveWatchScreen> createState() => _LiveWatchScreenState();
}

class _LiveWatchScreenState extends State<LiveWatchScreen> with SingleTickerProviderStateMixin {
  RtcEngine? _engine;
  bool _isJoined = false;
  int? _remoteUid;
  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;

  int _viewerCount = 1;
  int _giftCount = 0;
  
  late final AnimationController _giftPulseController;
  String? _giftPulseText;
  Timer? _giftPulseHideTimer;

  @override
  void initState() {
    super.initState();
    _giftPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _initAndJoin();
  }

  void _showGiftPulse(String giftName) {
    setState(() => _giftPulseText = giftName);
    _giftPulseHideTimer?.cancel();
    _giftPulseHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _giftPulseText = null);
    });
    _giftPulseController.forward(from: 0);
  }

  Future<void> _sendGift(GiftModel gift, String toHostId) async {
    try {
      if (mounted) {
        setState(() => _giftCount++);
        _showGiftPulse(gift.displayName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎁 Sent ${gift.displayName}!'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      developer.log('Send gift error: $e');
    }
  }

  void _showGiftPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftSelectionSheet(
        competitor1Id: widget.hostId ?? '',
        competitor1Name: widget.hostName,
        competitor2Id: widget.hostId ?? '',
        competitor2Name: widget.hostName,
        onGiftSelected: _sendGift,
      ),
    );
  }

  Future<void> _initAndJoin() async {
    try {
      if (!kIsWeb) {
        await [Permission.camera, Permission.microphone].request();
      }

      _engine = createAgoraRtcEngine();
      if (_engine == null) throw StateError('Failed to create Agora engine');

      final appId = AppEnv.agoraAppId.trim();
      await _engine!.initialize(RtcEngineContext(appId: appId));
      await _engine!.setChannelProfile(ChannelProfileType.channelProfileLiveBroadcasting);
      await _engine!.setClientRole(
        role: ClientRoleType.clientRoleAudience,
        options: const ClientRoleOptions(audienceLatencyLevel: AudienceLatencyLevelType.audienceLatencyLevelLowLatency),
      );
      await _engine!.enableVideo();

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            if (!_isDisposed) setState(() => _isJoined = true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            if (!_isDisposed) setState(() => _remoteUid = remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            if (!_isDisposed) setState(() => _remoteUid = null);
          },
        ),
      );

      await _engine!.joinChannel(
        token: '',
        channelId: widget.channelId,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: false,
          publishCameraTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
      
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _giftPulseHideTimer?.cancel();
    _giftPulseController.dispose();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          if (_engine != null && _remoteUid != null)
            AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine!,
                canvas: VideoCanvas(uid: _remoteUid!),
                connection: RtcConnection(channelId: widget.channelId),
              ),
            )
          else
            Container(color: Colors.black),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),

          Positioned(
            top: 50,
            left: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      SizedBox(width: 6),
                      Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text('$_viewerCount', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                widget.hostName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                ),
              ),
            ),
          ),

          if (_giftPulseText != null)
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _giftPulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1 + (1 - _giftPulseController.value) * 0.5,
                      child: Opacity(
                        opacity: 1 - _giftPulseController.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text('🎁 $_giftPulseText!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          Positioned(
            bottom: 80,
            right: 16,
            child: GestureDetector(
              onTap: _showGiftPicker,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                ),
                child: const Icon(Icons.card_giftcard, color: Colors.white, size: 28),
              ),
            ),
          ),

          if (_giftCount > 0)
            Positioned(
              bottom: 130,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text('$_giftCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),

          Positioned(
            top: 50,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Challenge Button - Only for Artists/DJs
          ChallengeButton(
            hostId: widget.hostId ?? '',
            hostName: widget.hostName,
            hostAvatar: '',
          ),
        ],
      ),
    );
  }
}
