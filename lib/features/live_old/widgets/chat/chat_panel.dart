import 'package:flutter/material.dart';

import '../../../../app/utils/app_result.dart';
import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/utils/user_facing_error.dart';
import '../../../../app/widgets/glass_card.dart';
import '../../models/chat_message_model.dart';
import '../../services/chat_service.dart';
import 'chat_message_bubble.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.liveId,
  });

  final String currentUserId;
  final String currentUserName;
  final String? liveId;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveId = (widget.liveId ?? '').trim();

    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE CHAT',
            style: TextStyle(
              color: WeAfricaColors.gold,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),

          // Chat messages
          Expanded(
            child: liveId.isEmpty
                ? const Center(
                    child: Text(
                      'Chat will appear when live starts.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : StreamBuilder<List<ChatMessageModel>>(
                    stream: ChatService()
                        .watchMessages(liveId: liveId, limit: 60),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        final msg = UserFacingError.message(
                          snap.error,
                          fallback: 'Chat is unavailable right now.',
                        );
                        return Center(
                          child: Text(
                            msg,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final messages = snap.data ?? const <ChatMessageModel>[];
                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return ChatMessageBubble(
                            message: msg,
                            isOwnMessage: msg.userId == widget.currentUserId,
                          );
                        },
                      );
                    },
                  ),
          ),

          // Message input
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Say something...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      border: InputBorder.none,
                    ),
                    enabled: liveId.isNotEmpty && !_sending,
                    onSubmitted: (v) => _sendMessage(liveId, v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: WeAfricaColors.gold, size: 20),
                onPressed: (liveId.isEmpty || _sending)
                    ? null
                    : () => _sendMessage(liveId, _controller.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String liveId, String text) async {
    final resolvedLiveId = liveId.trim();
    if (resolvedLiveId.isEmpty) return;

    final t = text.trim();
    if (t.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final res = await ChatService().sendMessage(
        liveId: resolvedLiveId,
        userId: widget.currentUserId,
        userName: widget.currentUserName.trim().isNotEmpty
            ? widget.currentUserName.trim()
            : 'User',
        message: t,
      );

      if (res is AppSuccess<void>) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      } else if (res is AppFailure<void>) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.userMessage ?? 'Could not send message.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}