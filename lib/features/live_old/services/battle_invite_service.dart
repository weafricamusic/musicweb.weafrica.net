import '../models/public_profile.dart';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle_host_api.dart';

/// Stores battle invites in Supabase.
///
/// Note: push notification delivery is typically handled server-side (trigger/edge function)
/// once an invite row is inserted.
class BattleInviteService {
  static final BattleInviteService _instance = BattleInviteService._internal();
  factory BattleInviteService() => _instance;
  BattleInviteService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendInvite({
    required String battleId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String battleType,
  }) async {
    if (toUserId.trim().isEmpty) return;

    try {
      // IMPORTANT: do not insert directly into `battle_invites`.
      // The server sends instant push notifications from the Edge API.
      // Direct DB inserts bypass that logic and result in “invite sent but no notification”.
      await const BattleHostApi().sendInviteToExistingBattle(
        battleId: battleId,
        toUid: toUserId,
      );
    } catch (e) {
      developer.log('sendInvite failed', error: e);
      rethrow;
    }
  }

  Future<void> updateInvitesWithBattleId({
    required String battleId,
    required String fromUserId,
  }) async {
    try {
      await _supabase
          .from('battle_invites')
          .update({'battle_id': battleId})
          .eq('from_user_id', fromUserId)
          .eq('battle_id', 'temp')
          .eq('status', 'pending');
    } catch (e) {
      developer.log('updateInvitesWithBattleId failed', error: e);
      rethrow;
    }
  }

  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) async {
    try {
      await _supabase.from('battle_invites').update({
        'status': accept ? 'accepted' : 'declined',
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', inviteId);
    } catch (e) {
      developer.log('respondToInvite failed', error: e);
      rethrow;
    }
  }

  Future<List<PublicProfile>> searchUsers({
    required String query,
    required String role,
    required String excludeUserId,
    int limit = 20,
  }) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('''
          id,
          username,
          display_name,
          avatar_url,
          role,
          updated_at
        ''')
          .eq('role', role)
          .neq('id', excludeUserId)
          .or('username.ilike.%$query%,display_name.ilike.%$query%')
          .order('updated_at', ascending: false)
          .limit(limit);

      return (response as List).map((json) => PublicProfile.fromJson(json)).toList();
    } catch (e) {
      developer.log('searchUsers failed', error: e);
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getPendingInvites(String userId) {
    return _supabase.from('battle_invites').stream(primaryKey: const ['id']).map((rows) {
      final filtered = rows
          .where((row) {
            final toUid = row['to_uid']?.toString();
            return toUid == userId;
          })
          .where((row) => row['status']?.toString() == 'pending')
          .toList(growable: false);

      filtered.sort((a, b) {
        final aDt = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bDt = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aDt == null && bDt == null) return 0;
        if (aDt == null) return 1;
        if (bDt == null) return -1;
        return bDt.compareTo(aDt);
      });

      return filtered;
    });
  }
}
