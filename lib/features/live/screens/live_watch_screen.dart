import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/config/app_env.dart';
import '../services/agora_token_api.dart';

class LiveWatchScreen extends StatefulWidget {
  final String channelId;
  final String hostName;
  final String? streamId;

  const LiveWatchScreen({
    super.key,
    required this.channelId,
    required this.hostName,
    this.streamId,
  });

  @override
  State<LiveWatchScreen> createState() => _LiveWatchScreenState();
}

class _LiveWatchScreenState extends State<LiveWatchScreen> {
  RtcEngine? _engine;
  bool _isJoined = false;
  int? _remoteUid;
  bool _isLoading = true;
  String? _error;
  String? _token;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initAndJoin();
  }

  Future<void> _initAndJoin() async {
    try {
      developer.log('Starting consumer join for channel: ${widget.channelId}');
      
      // 1. Request permissions (web handles this natively via browser prompt)
      if (!kIsWeb) {
        final perms = await [Permission.camera, Permission.microphone].request();
        developer.log('Permissions: camera=${perms[Permission.camera]}, mic=${perms[Permission.microphone]}');
      }

      // 2. Create engine
      _engine = createAgoraRtcEngine();
      if (_engine == null) throw StateError('Failed to create Agora engine');

      // 3. Initialize with App ID
      final appId = AppEnv.agoraAppId.trim();
      if (appId.isEmpty || appId == 'YOUR_AGORA_APP_ID') {
        throw StateError('Agora App ID not configured. Please set it in AppEnv');
      }
      
      developer.log('Initializing with App ID: ${appId.substring(0, 8)}...');
      
      await _engine!.initialize(RtcEngineContext(appId: appId));

      // 4. Set channel profile (CRITICAL - before enabling video)
      await _engine!.setChannelProfile(
        ChannelProfileType.channelProfileLiveBroadcasting,
      );
      developer.log('Channel profile set to LiveBroadcasting');

      // 5. Set client role to AUDIENCE (CRITICAL - not broadcaster)
      await _engine!.setClientRole(
        role: ClientRoleType.clientRoleAudience,
        options: const ClientRoleOptions(
          audienceLatencyLevel: AudienceLatencyLevelType.audienceLatencyLevelLowLatency,
        ),
      );
      developer.log('Client role set to Audience');

      // 6. Enable video (needed to receive stream)
      await _engine!.enableVideo();
      developer.log('Video enabled');

      // 7. Register event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            developer.log('✅ Joined channel: ${connection.channelId}, elapsed: $elapsed ms');
            if (!_isDisposed) {
              setState(() => _isJoined = true);
            }
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            developer.log('🎥 Host joined: $remoteUid');
            if (!_isDisposed) {
              setState(() => _remoteUid = remoteUid);
            }
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            developer.log('👋 Host left: $remoteUid, reason: $reason');
            if (!_isDisposed && remoteUid == _remoteUid) {
              setState(() => _remoteUid = null);
            }
          },
          onError: (ErrorCodeType err, String msg) {
            developer.log('❌ Agora error: $err - $msg');
            if (!_isDisposed) {
              setState(() => _error = 'Connection error: $msg (Code: ${err.value})');
            }
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            developer.log('Left channel: ${connection.channelId}');
          },
        ),
      );

      // 8. Get token for AUDIENCE role
      final tokenApi = AgoraTokenApi();
      _token = await tokenApi.fetchRtcToken(
        channelId: widget.channelId,
        role: AgoraRtcRole.audience,
        uid: 0,
      );
      developer.log('Token obtained: ${_token != null ? 'Yes' : 'No (test mode)'}');

      // 9. Join channel with audience options
      await _engine!.joinChannel(
        token: _token ?? '',
        channelId: widget.channelId,
        uid: 0,
        options: const ChannelMediaOptions(
          autoSubscribeVideo: true,
          autoSubscribeAudio: true,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          clientRoleType: ClientRoleType.clientRoleAudience,
        ),
      );
      developer.log('Join channel called');

      if (!_isDisposed) {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      developer.log('❌ Init error: $e\n$stackTrace');
      if (!_isDisposed) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to join: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _leaveAndDestroy();
    super.dispose();
  }

  Future<void> _leaveAndDestroy() async {
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
      _engine = null;
      developer.log('Engine released');
    } catch (e) {
      developer.log('Error releasing engine: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (host stream)
          if (_remoteUid != null && _engine != null)
            AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine!,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(channelId: widget.channelId),
              ),
            )
          else if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to live stream...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      _initAndJoin();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.live_tv, color: Colors.white54, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for host to start streaming...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // UI Overlay - Live Badge
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 8),
                  SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Host name
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                widget.hostName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
