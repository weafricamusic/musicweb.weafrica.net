import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../engine/live_engine_factory.dart';
import '../../../../widgets/agora_video_wrapper.dart';
import '../../data/services/firebase_live_service.dart';
import '../../data/services/firebase_chat_service.dart';
import '../../data/services/firebase_viewer_service.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/viewer_repository.dart';
import '../../state/live_session_cubit.dart';
import '../../core/enums/stream_status.dart';
import '../widgets/shared/chat_overlay.dart';
import '../widgets/shared/loading_live_view.dart';

/// Screen for watching a live stream (consumer/fan side).
class ConsumerLiveScreen extends StatefulWidget {
  final String liveSessionId;
  final String channelName;
  final String userId;
  final String userName;

  const ConsumerLiveScreen({
    super.key,
    required this.liveSessionId,
    required this.channelName,
    required this.userId,
    required this.userName,
  });

  @override
  State<ConsumerLiveScreen> createState() => _ConsumerLiveScreenState();
}

class _ConsumerLiveScreenState extends State<ConsumerLiveScreen> {
  late final LiveSessionCubit _cubit;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final supabase = Supabase.instance.client;
    final engine = LiveEngineFactory.create();
    final liveService = FirebaseLiveService(supabase);
    final chatService = FirebaseChatService(supabase);
    final viewerService = FirebaseViewerService(supabase);

    _cubit = LiveSessionCubit(
      engine: engine,
      sessionRepo: LiveSessionRepository(liveService),
      chatRepo: ChatRepository(chatService),
      viewerRepo: ViewerRepository(viewerService),
      userId: widget.userId,
      userName: widget.userName,
    );

    _cubit.addListener(_onStateChanged);
    _cubit.joinAsViewer(
      sessionId: widget.liveSessionId,
      channelName: widget.channelName,
    );
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _cubit.removeListener(_onStateChanged);
    _cubit.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    await _cubit.sendComment(text);
    _commentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = _cubit.value;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(state),
    );
  }

  Widget _buildBody(state) {
    if (state.status == StreamStatus.connecting) {
      return const LoadingLiveView(message: 'Joining live stream...');
    }

    if (state.status == StreamStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(state.errorMessage ?? 'Failed to join',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    }

    // Remote video UID (1) if remote video is available, 0 while waiting
    final remoteUid = _cubit.engine.remoteUid.value ?? 0;

    return GestureDetector(
      onDoubleTapDown: (_) {
        // Heart burst effect
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❤️'), duration: Duration(milliseconds: 500)),
        );
      },
      child: Stack(
        children: [
          // Remote video
          if (remoteUid > 0)
            AgoraVideoWrapper(
              rtcEngine: _cubit.engine.engine,
              uid: remoteUid,
            )
          else
            const Center(
              child: Text('Waiting for stream...',
                  style: TextStyle(color: Colors.white60)),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.person, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Live Host',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8),
                        _LiveBadge(),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('${state.viewerCount} watching',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),

          // Bottom: chat + leave
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatOverlay(
                    comments: state.comments,
                    controller: _commentController,
                    onSend: _sendComment,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.exit_to_app, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Leave',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
      child: const Text('LIVE',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}
