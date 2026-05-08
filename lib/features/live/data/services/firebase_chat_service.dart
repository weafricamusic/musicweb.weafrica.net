import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for live chat messages stored in Supabase.
class FirebaseChatService {
  final SupabaseClient _supabase;

  FirebaseChatService(this._supabase);

  /// Send a chat message to a live channel.
  Future<void> sendMessage({
    required String channelId,
    required String userId,
    required String username,
    required String text,
  }) async {
    await _supabase.from('live_chat_messages').insert({
      'channel_id': channelId,
      'user_id': userId,
      'username': username,
      'text': text,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Stream chat messages for a live channel in real-time.
  Stream<List<Map<String, dynamic>>> streamMessages(String channelId) {
    return _supabase
        .from('live_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('channel_id', channelId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((messages) => messages.reversed.toList());
  }
}
