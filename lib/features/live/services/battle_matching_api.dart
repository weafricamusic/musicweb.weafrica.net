import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/live_battle.dart';
import '../models/live_args.dart';

/// API for battle matching operations.
class BattleMatchingApi {
  const BattleMatchingApi();

  Future<List<BattleInvite>> listInvites({
    required String box,
    required String status,
    int limit = 25,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/invites');
      final res = await FirebaseAuthedHttp.get(
        Uri.parse('${uri.toString()}?box=$box&status=$status&limit=$limit'),
        requireAuth: true,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Battle invite list failed: ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body) as List;
      return decoded.map((m) => BattleInvite.fromMap(m as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Battle invite list error: $e');
      return const [];
    }
  }

  Future<LiveBattle> respondToInvite({
    required String inviteId,
    required String action,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/invites/respond');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'invite_id': inviteId, 'action': action}),
        requireAuth: true,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Respond failed: ${res.statusCode}');
      }
      return LiveBattle.fromMap(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Battle respond error: $e');
      rethrow;
    }
  }

  Future<LiveBattle?> quickMatchJoin({required String role}) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/quick_match/join');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'role': role}),
        requireAuth: true,
      );
      if (res.statusCode == 200) {
        return LiveBattle.fromMap(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Quick match join error: $e');
      return null;
    }
  }

  Future<LiveBattle?> quickMatchPoll() async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/quick_match/poll');
      final res = await FirebaseAuthedHttp.get(
        uri,
        requireAuth: true,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body == null) return null;
        return LiveBattle.fromMap(body as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Quick match poll error: $e');
      return null;
    }
  }

  Future<void> quickMatchCancel() async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/quick_match/cancel');
      await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: '{}',
        requireAuth: true,
      );
    } catch (e) {
      debugPrint('Quick match cancel error: $e');
    }
  }
}

// BattleInvite is now defined in ../models/live_battle.dart to avoid ambiguity
