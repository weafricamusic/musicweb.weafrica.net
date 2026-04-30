import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/agora_voice_service_web.dart';
import '../services/agora_token_api.dart';
import '../../../app/config/app_env.dart';

/// Voice calling screen for web platform.
/// Provides a UI for voice-only calls using Agora Web SDK.
class VoiceCallScreenWeb extends StatefulWidget {
  final String channelId;
  final String hostName;
  final bool isHost;
  final String? token;

  const VoiceCallScreenWeb({
    super.key,
    required this.channelId,
    required this.hostName,
    this.isHost = false,
    this.token,
  });

  @override
  State<VoiceCallScreenWeb> createState() => _VoiceCallScreenWebState();
}

class _VoiceCallScreenWebState extends State<VoiceCallScreenWeb> {
  final AgoraVoiceServiceWeb _voiceService = AgoraVoiceServiceWeb();
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isMuted = false;
  String? _error;
  int _connectionDuration = 0;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _initializeVoiceCall();
    _setupListeners();
  }

  Future<void> _initializeVoiceCall() async {
    setState(() => _isConnecting = true);

    try {
      final appId = AppEnv.agoraAppId;
      if (appId.isEmpty) {
        throw StateError('Agora App ID not configured');
      }

      String? token = widget.token;
      if (token == null || token.isEmpty) {
        // Fetch token from API
        final tokenApi = AgoraTokenApi();
        token = await tokenApi.fetchRtcToken(
          channelId: widget.channelId,
          role: widget.isHost ? AgoraRtcRole.broadcaster : AgoraRtcRole.audience,
          uid: 0,
        );
      }

      if (widget.isHost) {
        await _voiceService.joinVoiceChannel(
          appId: appId,
          channelId: widget.channelId,
          token: token,
        );
      } else {
        await _voiceService.joinAsAudience(
          appId: appId,
          channelId: widget.channelId,
          token: token,
        );
      }

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _connectionDuration++);
      });
    } catch (e) {
      debugPrint('Voice call initialization error: $e');
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    }
  }

  void _setupListeners() {
    _voiceService.onConnectionStateChanged.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });

    _voiceService.onRemoteUserJoined.listen((uid) {
      debugPrint('Remote user joined: $uid');
      // Could show a notification or update UI
    });

    _voiceService.onRemoteUserLeft.listen((uid) {
      debugPrint('Remote user left: $uid');
      // Could show a notification or update UI
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.purple.shade900,
                  Colors.black,
                ],
              ),
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Profile avatar
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade400, Colors.blue.shade400],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: ),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isHost ? Icons.mic : Icons.headset_mic,
                    size: 60,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 24),

                // Host name
                Text(
                  widget.hostName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                // Connection status
                if (_isConnecting)
                  const Text(
                    'Connecting...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  )
                else if (_isConnected)
                  Text(
                    _formatDuration(_connectionDuration),
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (_error != null)
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 48),

                // Controls
                if (_isConnected)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Mute button
                      _buildControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        onPressed: () async {
                          await _voiceService.toggleMute();
                          setState(() => _isMuted = !_isMuted);
                        },
                      ),

                      const SizedBox(width: 24),

                      // End call button
                      _buildControlButton(
                        icon: Icons.call_end,
                        label: 'End',
                        onPressed: () => Navigator.pop(context),
                        color: Colors.red,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Top app bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Voice Call',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // Spacer for balanced layout
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color ?? Colors.white24,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}