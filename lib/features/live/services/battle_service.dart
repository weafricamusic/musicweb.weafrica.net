import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../auth/user_role.dart';

class BattleService {
  Future<List<Map<String, dynamic>>> getPotentialOpponents({
    required String excludeUserId,
    required UserRole role,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/opponents/potential');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?exclude=$excludeUserId&role=${role.name}'),
        requireAuth: true,
      );
      
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as List;
        return decoded.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      }
      return const [];
    } catch (e) {
      debugPrint('BattleService: getPotentialOpponents error: $e');
      return const [];
    }
  }

  Future<void> sendBattleInvite({
    required String battleId,
    required String channelId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String battleTitle,
    required int durationSeconds,
    required int coinGoal,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/invite/send');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'battle_id': battleId,
          'channel_id': channelId,
          'from_uid': fromUserId,
          'from_user_name': fromUserName,
          'to_uid': toUserId,
          'title': battleTitle,
          'duration_seconds': durationSeconds,
          'coin_goal': coinGoal,
        }),
        requireAuth: true,
      );
      
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Failed to send invite: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('BattleService: sendBattleInvite error: $e');
      rethrow;
    }
  }
}
