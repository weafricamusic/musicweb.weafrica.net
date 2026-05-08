import 'package:flutter/material.dart';

class ChatOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> comments;
  final TextEditingController controller;
  final VoidCallback onSend;

  const ChatOverlay({
    super.key,
    required this.comments,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          child: ListView.builder(
            reverse: true,
            itemCount: comments.length,
            itemBuilder: (_, i) {
              final c = comments[comments.length - 1 - i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${c['username'] ?? 'User'} ',
                          style: const TextStyle(
                            color: Color(0xFFFF9F0A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: c['text'],
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Say something...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: const Icon(Icons.send, color: Colors.blueAccent),
            ),
          ],
        ),
      ],
    );
  }
}
