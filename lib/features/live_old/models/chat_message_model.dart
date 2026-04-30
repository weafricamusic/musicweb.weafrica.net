class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.message,
    required this.timestamp,
    required this.isGift,
  });

  final String id;
  final String userId;
  final String userName;
  final String message;
  final DateTime timestamp;
  final bool isGift;
}
