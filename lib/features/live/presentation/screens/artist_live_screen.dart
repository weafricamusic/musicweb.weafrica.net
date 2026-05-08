import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../engine/live_engine_factory.dart';
import '../../engine/live_engine_interface.dart';
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

/// Solo or battle broadcast screen for artists.
class ArtistLiveScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String title;
  final String? category;

  const ArtistLiveScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.title,
    this.category,
  });

  @override
  State<ArtistLiveScreen> createState() => _ArtistLiveScreenState();
}

class _ArtistLiveScreenState extends State<ArtistLiveScreen> {
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
    _cubit.startSoloLive(title: widget.title, category: widget.category);
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

  Future<void> _endLive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End Live?'),
        content: const Text('Are you sure you want to end your live stream?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End')),
        ],
      ),
    );
    if (confirmed == true) {
      await _cubit.endLive();
      if (mounted) Navigator.pop(context);
    }
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
      return const LoadingLiveView(message: 'Starting your live stream...');
    }

    if (state.status == StreamStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(state.errorMessage ?? 'An error occurred',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Video background — mobile renders via plugin, web via DOM overlay
        if (_cubit.engine is LiveEngineInterface)
          AgoraVideoWrapper(
            rtcEngine: _cubit.engine.engine,
            uid: 0,
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
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(widget.userName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const _LiveIndicator(),
                    ],
                  ),
                ),
                const Spacer(),
                Text('${state.viewerCount} viewers',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),

        // Camera controls
        Positioned(
          right: 16,
          top: MediaQuery.of(context).size.height * 0.35,
          child: Column(
            children: [
              _controlButton(Icons.flip_camera_ios, () => _cubit.switchCamera()),
              const SizedBox(height: 16),
              _controlButton(
                  state.isMuted ? Icons.mic_off : Icons.mic, () => _cubit.toggleMute()),
              const SizedBox(height: 16),
              _controlButton(
                  state.isVideoOff ? Icons.videocam_off : Icons.videocam, () => _cubit.toggleVideo()),
            ],
          ),
        ),

        // Bottom: chat + end button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
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
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _endLive,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('END', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
      child: const Text('LIVE',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
    );
  }
}
