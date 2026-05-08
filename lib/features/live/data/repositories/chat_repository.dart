import '../services/firebase_chat_service.dart';

/// Repository for live chat messages.
class ChatRepository {
  final FirebaseChatService _chatService;

  ChatRepository(this._chatService);

  Future<void> sendMessage({
    required String channelId,
    required String userId,
    required String username,
    required String text,
  }) {
    return _chatService.sendMessage(
      channelId: channelId,
      userId: userId,
      username: username,
      text: text,
    );
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String channelId) {
    return _chatService.streamMessages(channelId);
  }
}
