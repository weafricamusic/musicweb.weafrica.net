import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/battle_request_model.dart';

/// Service for sending and receiving battle invitations.
class BattleRequestService {
  final SupabaseClient _supabase;

  BattleRequestService(this._supabase);

  /// Send a battle request to another artist.
  Future<void> sendRequest({
    required String sessionId,
    required String fromUserId,
    required String fromUserName,
    String? fromAvatarUrl,
    required String toUserId,
  }) async {
    await _supabase.from('battle_requests').insert({
      'session_id': sessionId,
      'from_user_id': fromUserId,
      'from_user_name': fromUserName,
      'from_avatar_url': fromAvatarUrl,
      'to_user_id': toUserId,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Accept a pending battle request.
  Future<void> acceptRequest(String sessionId, String fromUserId) async {
    await _supabase
        .from('battle_requests')
        .update({'status': 'accepted'})
        .eq('session_id', sessionId)
        .eq('from_user_id', fromUserId);
  }

  /// Decline a pending battle request.
  Future<void> declineRequest(String sessionId, String fromUserId) async {
    await _supabase
        .from('battle_requests')
        .update({'status': 'declined'})
        .eq('session_id', sessionId)
        .eq('from_user_id', fromUserId);
  }

  /// Stream incoming battle requests for an artist.
  Stream<List<BattleRequestModel>> streamRequests(String userId) {
    return _supabase
        .from('battle_requests')
        .stream(primaryKey: ['id'])
        .map((list) => list
            .where((e) => e['to_user_id'] == userId && e['status'] == 'pending')
            .map((e) => BattleRequestModel.fromJson(e))
            .toList());
  }
}
