import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Service for managing gifts in live sessions
class GiftService {
  final _client = SupabaseService.client;

  /// Send a gift to a live session host
  Future<void> sendGift({
    required String sessionId,
    required String hostId,
    required String giftType,
    required double amount,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _client.from('live_gifts').insert({
      'live_session_id': sessionId,
      'sender_id': user.id,
      'sender_name': user.userMetadata?['username'] ?? user.email ?? 'User',
      'recipient_id': hostId,
      'gift_type': giftType,
      'amount': amount,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Increment gift count on session
    await _client.rpc(
      'increment_gift_count',
      params: {'session_id': sessionId},
    );
  }

  /// Get total gifts for a session
  Future<double> getTotalGifts(String sessionId) async {
    final response = await _client
        .from('live_gifts')
        .select('amount')
        .eq('live_session_id', sessionId);

    final gifts = response as List;
    return gifts.fold<double>(
      0,
      (sum, gift) => sum + (gift['amount'] as num).toDouble(),
    );
  }

  /// Get gift leaderboard for a session
  Future<List<Map<String, dynamic>>> getGiftLeaderboard(String sessionId) async {
    final response = await _client
        .from('live_gifts')
        .select('sender_name, amount')
        .eq('live_session_id', sessionId)
        .order('amount', ascending: false)
        .limit(10);

    return response as List<Map<String, dynamic>>;
  }
}