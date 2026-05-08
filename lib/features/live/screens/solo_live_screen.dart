import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../providers/live_session_provider.dart';
import '../providers/comment_provider.dart';
import '../providers/auth_provider.dart';
import '../../../data/services/agora_service.dart' show AgoraRole;
import '../../../data/providers/service_providers.dart';

class SoloLiveScreen extends ConsumerStatefulWidget {
  const SoloLiveScreen({super.key});

  @override
  ConsumerState<SoloLiveScreen> createState() => _SoloLiveScreenState();
}

class _SoloLiveScreenState extends ConsumerState<SoloLiveScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isInitializing = false;
  String? _initError;
  bool _isEnding = false;

  @override
  void initState() {
    super.initState();
    _initializeAndJoin();
  }

  Future<void> _initializeAndJoin() async {
    // Prevent double-init
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      debugPrint('SOLO LIVE: waiting for live session...');

      final session = await ref.read(liveSessionProvider.future);

      if (!mounted) {
        _isInitializing = false;
        return;
      }

      if (session == null) {
        debugPrint('SOLO LIVE ERROR: live session is null');
        _initError = 'Failed to load live session data. Please try again.';
        if (mounted) setState(() {});
        _isInitializing = false;
        return;
      }

      final channelName = session['channel_id']?.toString();

      if (channelName == null || channelName.isEmpty) {
        debugPrint('SOLO LIVE ERROR: channel_id is missing');
        _initError = 'Channel ID is missing. Please restart the stream.';
        if (mounted) setState(() {});
        _isInitializing = false;
        return;
      }

      debugPrint('SOLO LIVE: joining Agora channel $channelName');

      final agora = ref.read(agoraServiceProvider);
      await agora.joinChannel(
        channelName: channelName,
        role: AgoraRole.broadcaster,
      );

      debugPrint('SOLO LIVE: Agora joinChannel completed');

      if (!mounted) {
        // Widget disposed during join — leave channel to clean up Agora state
        try {
          await agora.leaveChannel();
        } catch (_) {}
        _isInitializing = false;
        return;
      }

      // On web, create DOM overlay for camera video
      agora.createVideoOverlay();

      ref.read(presenceReconciliationProvider).start();
      _startHeartbeat(channelName);

      _isInitializing = false;
    } catch (e, st) {
      debugPrint('SOLO LIVE ERROR: _initializeAndJoin failed: $e\n$st');
      _initError = 'Failed to start live stream: ${e.toString()}';
      _isInitializing = false;
      // Cancel any running heartbeat on error
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      if (mounted) setState(() {});
    }
  }

  Timer? _heartbeatTimer;

  void _startHeartbeat(String channelName) {
    // Cancel any existing heartbeat first
    _heartbeatTimer?.cancel();
    final svc = ref.read(liveSessionService);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        svc.heartbeat(channelId: channelName);
      } catch (e) {
        debugPrint('SOLO LIVE: heartbeat failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _commentController.dispose();
    // The ref may be unusable during dispose on native — the AgoraService
    // is disposed by its own Provider.dispose callback.
    super.dispose();
  }

  void _toggleMute() {
    ref.read(agoraServiceProvider).toggleMute();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    ref.read(agoraServiceProvider).toggleVideo();
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _flipCamera() {
    ref.read(agoraServiceProvider).switchCamera();
  }

  Future<void> _endLive() async {
    // Prevent double-tap ending
    if (_isEnding) return;
    _isEnding = true;

    debugPrint('SOLO LIVE: Showing end live confirmation dialog');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('End Live?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end your live stream?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _isEnding = false;
      return;
    }

    try {
      final agora = ref.read(agoraServiceProvider);
      agora.removeVideoOverlay();
      await agora.leaveChannel();
      await ref.read(liveSessionProvider.notifier).endLive();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('SOLO LIVE ERROR: Failed to end live: $e');
      _isEnding = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to end live: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final sessionId = ref.read(liveSessionProvider.notifier).currentSessionId;
    if (sessionId == null) return;

    try {
      await ref.read(sendCommentProvider)(sessionId, text);
      _commentController.clear();
    } catch (e) {
      debugPrint('SOLO LIVE: send comment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send comment. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agoraService = ref.watch(agoraServiceProvider);
    final sessionAsync = ref.watch(liveSessionProvider);
    final currentSessionId =
        ref.watch(liveSessionProvider.notifier).currentSessionId;
    final commentsAsync = ref.watch(commentsProvider(currentSessionId ?? ''));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Loading / background
          if (_initError != null)
            // Error state — show error with retry
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _initError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          _initError = null;
                          _initializeAndJoin();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text('Go Back',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ValueListenableBuilder<bool>(
              valueListenable: agoraService.isJoined,
              builder: (context, isJoined, child) {
                if (!isJoined) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandBlue,
                      ),
                    ),
                  );
                }
                // Transparent — video renders via DOM overlay (web) or
                // native AgoraVideoView placed behind the Flutter canvas.
                return const SizedBox.expand();
              },
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              color: Colors.grey.shade900,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      sessionAsync.value?['host_name']
                                              ?.toString() ??
                                          'Live Host',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                sessionAsync.when(
                                  data: (session) => Text(
                                    '${session?['viewer_count'] ?? 0} viewers',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, _) => const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right side camera controls
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.35,
            child: Column(
              children: [
                _camControlButton(Icons.flip_camera_ios, _flipCamera),
                const SizedBox(height: 16),
                _camControlButton(
                  _isCameraOff ? Icons.videocam_off : Icons.videocam,
                  _toggleCamera,
                  active: _isCameraOff,
                ),
                const SizedBox(height: 16),
                _camControlButton(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  _toggleMute,
                  active: _isMuted,
                ),
              ],
            ),
          ),

          // Bottom section
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Comments
                  SizedBox(
                    height: 120,
                    child: commentsAsync.when(
                      data: (comments) {
                        final allComments = comments;
                        return ListView.builder(
                          reverse: true,
                          itemCount: allComments.length,
                          itemBuilder: (context, index) {
                            final comment =
                                allComments[allComments.length - 1 - index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: comment['user_id'] ==
                                              ref.read(currentUserProvider).value?.id
                                          ? Colors.blue.withValues(alpha: 0.3)
                                          : Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${comment['username'] ?? 'User'} ',
                                            style: const TextStyle(
                                              color: AppColors.brandGold,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(
                                            text: comment['text'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandBlue,
                        ),
                      ),
                      error: (_, __) => const Center(
                        child: Text(
                          'Comments error',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Input row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.emoji_emotions,
                                  color: Colors.white.withValues(alpha: 0.5)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Say something...',
                                    hintStyle: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5)),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _sendComment(),
                                ),
                              ),
                              GestureDetector(
                                onTap: _sendComment,
                                child: const Icon(Icons.send, color: Colors.blueAccent),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F0A).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFFF9F0A).withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.card_giftcard,
                            color: AppColors.brandGold),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _endLive,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.stop, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'END',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _camControlButton(
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}