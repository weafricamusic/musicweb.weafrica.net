import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../models/chat_message_model.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwnMessage,
  });

  final ChatMessageModel message;
  final bool isOwnMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar for other users
          if (!isOwnMessage) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: WeAfricaColors.gold.withValues(alpha: 0.2),
              child: Text(
                message.userName.isEmpty
                    ? '?'
                    : message.userName[0].toUpperCase(),
                style: const TextStyle(
                  color: WeAfricaColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Message bubble
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOwnMessage
                    ? WeAfricaColors.gold.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOwnMessage
                      ? WeAfricaColors.gold.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isOwnMessage)
                    Text(
                      message.userName,
                      style: const TextStyle(
                        color: WeAfricaColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isOwnMessage ? WeAfricaColors.gold : Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Small spacing for own messages
          if (isOwnMessage) const SizedBox(width: 8),
        ],
      ),
    );
  }
}