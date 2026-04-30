import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../auth/user_role.dart';
import '../../auth/user_role_resolver.dart';
import '../models/battle_model.dart';
import '../models/stream_challenge.dart';
import 'battle_host_api.dart';
import 'live_challenges_api.dart';

class BattleLookupResult {
  const BattleLookupResult({this.data});

  final BattleModel? data;
}

class BattleService {
  BattleService({
    LiveChallengesApi? api,
    ApiUriBuilder? uriBuilder,
    SupabaseClient? supabase,
    BattleHostApi? hostApi,
  })  : _api = api ?? LiveChallengesApi(),
        _uriBuilder = uriBuilder ?? const ApiUriBuilder(),
        _supabase = supabase ?? Supabase.instance.client,
        _hostApi = hostApi ?? const BattleHostApi();

  final LiveChallengesApi _api;
  final ApiUriBuilder _uriBuilder;
  final SupabaseClient _supabase;
  final BattleHostApi _hostApi;

  static const Duration _requestTimeout = Duration(seconds: 12);

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  String _asString(Object? value) => (value ?? '').toString().trim();

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_asString(value)) ?? 0;
  }

  Future<Map<String, String>> _loadNamesByUserIds(Iterable<String> ids) async {
    final wanted = ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (wanted.isEmpty) return const <String, String>{};

    try {
      final rows = await _supabase
          .from('profiles')
          .select('id,display_name,username')
          .inFilter('id', wanted);

      final result = <String, String>{};
      for (final row in (rows as List).whereType<Map>()) {
        final map = row.map((k, v) => MapEntry(k.toString(), v));
        final id = _asString(map['id']);
        if (id.isEmpty) continue;
        final displayName = _asString(map['display_name']);
        final username = _asString(map['username']);
        result[id] = displayName.isNotEmpty ? displayName : (username.isNotEmpty ? username : id);
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  int _timeRemainingFromRow(Map<String, dynamic> row) {
    final endsAt = DateTime.tryParse(_asString(row['ends_at']));
    if (endsAt != null) {
      final seconds = endsAt.difference(DateTime.now().toUtc()).inSeconds;
      if (seconds > 0) return seconds;
    }

    final direct = _toInt(row['time_remaining']);
    if (direct > 0) return direct;

    final duration = _toInt(row['duration_seconds']);
    if (duration > 0) return duration;

    return 1800;
  }

  Future<BattleModel?> _mapBattleRow(Map<String, dynamic> row) async {
    final battleId = _asString(row['battle_id']).isNotEmpty ? _asString(row['battle_id']) : _asString(row['id']);
    if (battleId.isEmpty) return null;

    final competitor1Id = _asString(row['host_a_id']);
    final competitor2Id = _asString(row['host_b_id']);
    if (competitor1Id.isEmpty || competitor2Id.isEmpty) {
      throw StateError('Battle payload missing host IDs');
    }

    final names = await _loadNamesByUserIds(<String>[competitor1Id, competitor2Id]);
    final competitor1Name = _asString(row['host_a_name']).isNotEmpty
        ? _asString(row['host_a_name'])
        : (_asString(row['competitor1_name']).isNotEmpty
            ? _asString(row['competitor1_name'])
            : (names[competitor1Id] ?? 'Host'));
    final competitor2Name = _asString(row['host_b_name']).isNotEmpty
        ? _asString(row['host_b_name'])
        : (_asString(row['competitor2_name']).isNotEmpty
            ? _asString(row['competitor2_name'])
            : (names[competitor2Id] ?? (competitor2Id.isNotEmpty ? 'Opponent' : 'Waiting')));

    final role = _asString(row['battle_type']).isNotEmpty
        ? _asString(row['battle_type'])
        : (_asString(row['competitor1_type']).isNotEmpty ? _asString(row['competitor1_type']) : 'artist');

    return BattleModel(
      id: battleId,
      competitor1Id: competitor1Id,
      competitor2Id: competitor2Id,
      competitor1Name: competitor1Name,
      competitor2Name: competitor2Name,
      competitor1Type: role,
      competitor2Type: _asString(row['competitor2_type']).isNotEmpty ? _asString(row['competitor2_type']) : role,
      competitor1Score: _toInt(row['host_a_score']),
      competitor2Score: _toInt(row['host_b_score']),
      timeRemaining: _timeRemainingFromRow(row),
      winnerId: _asString(row['winner_uid']).isNotEmpty ? _asString(row['winner_uid']) : null,
    );
  }

  Future<BattleModel?> _fetchBattleFromEdge(String battleId) async {
    final token = (await FirebaseAuth.instance.currentUser?.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw StateError('Authentication token unavailable');
    }

    final uri = _uriBuilder.build(
      '/api/battle/status',
      queryParameters: <String, String>{'battle_id': battleId},
    );
    final res = await http.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(_requestTimeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('getBattle failed (${res.statusCode})');
    }

    final decoded = _decodeMap(res.body);
    if (decoded == null) {
      throw StateError('Invalid battle response shape');
    }
    final raw = decoded['battle'] ?? decoded['data'] ?? decoded['result'];
    if (raw is! Map) {
      throw StateError('Battle payload missing in response');
    }
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    return _mapBattleRow(map);
  }

  Future<BattleLookupResult> getBattle(String sessionId, {String? battleId}) async {
    final requestedBattleId = _asString(battleId).isNotEmpty ? _asString(battleId) : _asString(sessionId);
    if (requestedBattleId.isEmpty) {
      return const BattleLookupResult();
    }

    final edgeBattle = await _fetchBattleFromEdge(requestedBattleId);
    return BattleLookupResult(data: edgeBattle);
  }

  Future<List<Map<String, dynamic>>> getPotentialOpponents({
    required String excludeUserId,
    UserRole? role,
  }) async {
    final resolvedRole = role ?? await UserRoleResolver.resolveCurrentUser(client: _supabase);
    final roleId = resolvedRole == UserRole.dj ? UserRole.dj.id : UserRole.artist.id;

    try {
      final rows = await _supabase
          .from('profiles')
          .select('id,display_name,username,role')
          .eq('role', roleId)
          .neq('id', excludeUserId)
          .order('updated_at', ascending: false)
          .limit(25);

      return (rows as List)
          .whereType<Map>()
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .map((row) {
            final name = _asString(row['display_name']).isNotEmpty
                ? _asString(row['display_name'])
                : (_asString(row['username']).isNotEmpty ? _asString(row['username']) : 'Artist');
            return <String, dynamic>{
              'id': _asString(row['id']),
              'name': name,
              'category': resolvedRole == UserRole.dj ? 'DJ' : 'Artist',
            };
          })
          .where((row) => _asString(row['id']).isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
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
    if (kDebugMode) {
      debugPrint('📨 BattleService.sendBattleInvite start battleId=$battleId to=$toUserId from=$fromUserId channelId=$channelId');
    }
    try {
      await _hostApi.sendInviteToExistingBattle(
        battleId: battleId,
        toUid: toUserId,
      );
      if (kDebugMode) {
        debugPrint('✅ BattleService.sendBattleInvite success battleId=$battleId to=$toUserId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ BattleService.sendBattleInvite failed: $e');
      }
      rethrow;
    }
  }

  Future<StreamChallenge> sendChallenge({
    required String targetUserId,
    required String beatId,
    required int betAmount,
    String? beatName,
    String? beatGenre,
    int? beatDuration,
  }) async {
    final beatLabel = (beatName ?? '').trim();
    final genreLabel = (beatGenre ?? '').trim();

    final msg = beatLabel.isNotEmpty
        ? 'I challenge you to a $beatLabel battle for $betAmount coins!'
        : 'I challenge you to a battle for $betAmount coins!';

    return _api.sendChallenge(
      targetUserId: targetUserId,
      message: msg,
      metadata: <String, dynamic>{
        'beatId': beatId,
        'betAmount': betAmount,
        if (beatLabel.isNotEmpty) 'beatName': beatLabel,
        if (genreLabel.isNotEmpty) 'beatGenre': genreLabel,
        if (beatDuration != null && beatDuration > 0) 'beatDuration': beatDuration,
      },
    );
  }

  Future<Map<String, dynamic>> acceptChallenge(String challengeId) async {
    return _api.acceptChallenge(challengeId: challengeId);
  }

  Future<List<StreamChallenge>> getPendingChallenges() {
    return _api.listPendingChallenges();
  }
}
