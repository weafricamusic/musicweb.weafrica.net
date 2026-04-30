import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/battle_invite.dart';
import '../models/live_battle.dart';

export '../models/battle_invite.dart' show BattleInvite;

/// Compatibility API used by older dashboard screens.
///
/// Newer Live/Battle flows use `PreLiveStudioScreen` + Edge APIs.
/// This keeps existing creator dashboards compiling and working.
class BattleMatchingApi {
  const BattleMatchingApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;
  static const Duration _timeout = Duration(seconds: 20);

  Future<List<BattleInvite>> listInvites({
    required String box,
    required String status,
    int limit = 25,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const <BattleInvite>[];
    }

    final uri = _uriBuilder.build(
      '/api/battle/invites',
      queryParameters: <String, String>{
        'box': box,
        'status': status,
        'limit': '$limit',
      },
    );
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
      },
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('listInvites failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Invalid invites response shape');
    }

    final rawInvites = decoded['invites'] ?? decoded['data'] ?? decoded['result'];
    if (rawInvites is! List) {
      throw StateError('Invites payload missing list');
    }

    return rawInvites
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map(BattleInvite.fromMap)
        .toList(growable: false);
  }

  Future<LiveBattle> respondToInvite({
    required String inviteId,
    required String action,
  }) async {
    final act = action.trim().toLowerCase();
    if (act != 'accept' && act != 'decline') {
      throw ArgumentError('action must be accept or decline');
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Authentication token unavailable');
    }

    final uri = _uriBuilder.build('/api/battle/invite/respond');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'invite_id': inviteId,
        'action': act,
      }),
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('respondToInvite failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Invalid invite response shape');
    }

    final raw = decoded['battle'] ?? decoded['data'] ?? decoded['result'];
    if (raw is! Map) {
      throw StateError('Battle payload missing after invite response');
    }

    final battleMap = raw.map((k, v) => MapEntry(k.toString(), v));
    return LiveBattle.fromMap(Map<String, dynamic>.from(battleMap));
  }

  /// Not yet implemented in the new flow; kept for compatibility.
  Future<LiveBattle?> quickMatchJoin({required String role}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Authentication token unavailable');
    }

    final uri = _uriBuilder.build('/api/battle/quick_match/join');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'role': role.trim().isEmpty ? 'artist' : role.trim().toLowerCase(),
      }),
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('quickMatchJoin failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Invalid quick match join response shape');
    }

    final matched = decoded['matched'] == true;
    if (!matched) return null;

    final raw = decoded['battle'];
    if (raw is! Map) {
      throw StateError('Quick match join missing battle payload');
    }

    final battleMap = raw.map((k, v) => MapEntry(k.toString(), v));
    return LiveBattle.fromMap(Map<String, dynamic>.from(battleMap));
  }

  /// Not yet implemented in the new flow; kept for compatibility.
  Future<LiveBattle?> quickMatchPoll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Authentication token unavailable');
    }

    final uri = _uriBuilder.build('/api/battle/quick_match/poll');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
      },
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('quickMatchPoll failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Invalid quick match poll response shape');
    }

    final matched = decoded['matched'] == true;
    if (!matched) return null;

    final raw = decoded['battle'];
    if (raw is! Map) {
      throw StateError('Quick match poll missing battle payload');
    }

    final battleMap = raw.map((k, v) => MapEntry(k.toString(), v));
    return LiveBattle.fromMap(Map<String, dynamic>.from(battleMap));
  }

  /// Not yet implemented in the new flow; kept for compatibility.
  Future<void> quickMatchCancel() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return;
    }

    final uri = _uriBuilder.build('/api/battle/quick_match/cancel');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(const <String, Object?>{}),
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('quickMatchCancel failed (${res.statusCode})');
    }
  }
}
