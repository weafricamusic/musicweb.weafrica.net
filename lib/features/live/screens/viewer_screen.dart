import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../data/services/agora_service.dart';
import '../../../app/theme.dart';
import '../providers/agora_provider.dart';
import '../providers/viewer_provider.dart';
import '../providers/comment_provider.dart';
import '../providers/auth_provider.dart';

class ViewerScreen extends ConsumerStatefulWidget {
  final String liveSessionId;
  final String channelName;

  const ViewerScreen({
    super.key,
    required this.liveSessionId,
    required this.channelName,
  });

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  final TextEditingController _commentController = TextEditingController();
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeAndJoin();
  }

  Future<void> _initializeAndJoin() async {
    await ref.read(agoraInitializedProvider.future);

    final agora = ref.read(agoraServiceProvider);
    await agora.joinChannel(
      channelName: widget.channelName,
      role: AgoraRole.audience,
    );

    // Track viewer presence
    await ref.read(joinLiveProvider)(widget.liveSessionId);

    // On web: create DOM overlay when remote video arrives
    if (kIsWeb) {
      _setupRemoteVideoWatcher();
    }
  }

  void _setupRemoteVideoWatcher() {
    final agora = ref.read(agoraServiceProvider);
    agora.remoteUid.addListener(() {
      if (agora.remoteUid.value != null) {
        agora.createRemoteVideoOverlay();
      }
    });
    // Check immediately in case already set
    if (agora.remoteUid.value != null) {
      agora.createRemoteVideoOverlay();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    if (kIsWeb) {
      ref.read(agoraServiceProvider).removeVideoOverlay();
    }
    ref.read(leaveLiveProvider)();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    await ref.read(sendCommentProvider)(widget.liveSessionId, text);
    _commentController.clear();
  }

  void _showLikeBurst(TapDownDetails details) {
    setState(() => _likeCount += 3);

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: details.globalPosition.dx - 15,
        top: details.globalPosition.dy - 15,
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          builder: (context, value, child) {
            return Opacity(
              opacity: 1 - value,
              child: Transform.translate(
                offset: Offset(0, -150 * value),
                child: Transform.scale(
                  scale: 1 + value * 0.5,
                  child: const Text('❤️', style: TextStyle(fontSize: 28)),
                ),
              ),
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1200), () => entry.remove());
  }

  @override
  Widget build(BuildContext context) {
    final agoraService = ref.watch(agoraServiceProvider);
    final viewerCount = ref.watch(viewerCountProvider(widget.liveSessionId));
    final commentsAsync = ref.watch(commentsProvider(widget.liveSessionId));

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTapDown: _showLikeBurst,
        child: Stack(
          children: [
            // Remote video background
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
                      child: CircularProgressIndicator(color: AppColors.brandBlue),
                    ),
                  );
                }

                return ValueListenableBuilder<int?>(
                  valueListenable: agoraService.remoteUid,
                  builder: (context, remoteUid, child) {
                  if (remoteUid == null) {
                    return Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Waiting for stream...',
                          style: TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                      ),
                    );
                  }
                  // Transparent — video renders via DOM overlay (web) or
                  // native AgoraVideoView placed behind the Flutter canvas.
                  return const SizedBox.expand();
                  },
                );
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
                                image: const DecorationImage(
                                  image: NetworkImage(
                                      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Live Host',
                                        style: TextStyle(
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
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility, size: 14, color: Colors.blueAccent),
                          const SizedBox(width: 6),
                          viewerCount.when(
                            data: (count) => Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            loading: () => const SizedBox(
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            error: (_, __) =>
                                const Text('0', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
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
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 140,
                      child: commentsAsync.when(
                        data: (comments) => ListView.builder(
                          itemCount: comments.length,
                          itemBuilder: (context, index) {
                            final comment = comments[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
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
                        ),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.brandBlue),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                                  child:
                                      const Icon(Icons.send, color: Colors.blueAccent),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9F0A).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.4)),
                            ),
                            child:
                                const Icon(Icons.card_giftcard, color: AppColors.brandGold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.exit_to_app, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Leave',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
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
      ),
    );
  }
}