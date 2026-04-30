import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/utils/app_result.dart';

class BattleChatEntry {
  const BattleChatEntry({
    required this.id,
    required this.battleId,
    required this.userId,
    required this.userName,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String battleId;
  final String userId;
  final String userName;
  final String message;
  final DateTime createdAt;

  factory BattleChatEntry.fromRow(Map<String, dynamic> row) {
    String s(Object? value) => (value ?? '').toString().trim();

    return BattleChatEntry(
      id: s(row['id']),
      battleId: s(row['battle_id']),
      userId: s(row['user_id']),
      userName: s(row['user_name']).isNotEmpty ? s(row['user_name']) : 'Fan',
      message: s(row['message']),
      createdAt: DateTime.tryParse(s(row['created_at']))?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

class BattleRequestEntry {
  const BattleRequestEntry({
    required this.id,
    required this.battleId,
    required this.requesterId,
    required this.requesterName,
    required this.status,
    required this.createdAt,
    this.avatarUrl,
  });

  final String id;
  final String battleId;
  final String requesterId;
  final String requesterName;
  final String status;
  final DateTime createdAt;
  final String? avatarUrl;

  bool get isPending => status == 'pending';

  BattleRequestEntry copyWith({
    String? requesterName,
    String? avatarUrl,
  }) {
    return BattleRequestEntry(
      id: id,
      battleId: battleId,
      requesterId: requesterId,
      requesterName: requesterName ?? this.requesterName,
      status: status,
      createdAt: createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  factory BattleRequestEntry.fromRow(Map<String, dynamic> row) {
    String s(Object? value) => (value ?? '').toString().trim();

    return BattleRequestEntry(
      id: s(row['id']),
      battleId: s(row['battle_id']),
      requesterId: s(row['requester_id']),
      requesterName: 'Requester',
      status: s(row['status']).isNotEmpty ? s(row['status']) : 'pending',
      createdAt: DateTime.tryParse(s(row['created_at']))?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

class BattleVoteSummary {
  const BattleVoteSummary({
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Votes,
    required this.competitor2Votes,
    required this.myVote,
  });

  final String competitor1Id;
  final String competitor2Id;
  final int competitor1Votes;
  final int competitor2Votes;
  final String? myVote;

  int get totalVotes => competitor1Votes + competitor2Votes;
}

class AcceptedBattleRequest {
  const AcceptedBattleRequest({
    required this.requestId,
    required this.requesterId,
  });

  final String requestId;
  final String requesterId;
}

class BattleInteractionsService {
  static final BattleInteractionsService _instance =
      BattleInteractionsService._internal();

  factory BattleInteractionsService() => _instance;

  BattleInteractionsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  static const Duration _requestTimeout = Duration(seconds: 10);

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore invalid payloads
    }
    return null;
  }

  Stream<List<BattleChatEntry>> watchChat({
    required String battleId,
    int limit = 40,
  }) {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      return const Stream<List<BattleChatEntry>>.empty();
    }

    try {
      return _supabase
          .from('battle_chat')
          .stream(primaryKey: const ['id'])
          .eq('battle_id', bid)
          .order('created_at', ascending: false)
          .limit(limit)
          .map(
            (rows) => rows
                .map((row) => BattleChatEntry.fromRow(Map<String, dynamic>.from(row)))
                .toList(growable: false),
          );
    } catch (e) {
      developer.log('watchChat failed', name: 'WEAFRICA.Live', error: e);
      return const Stream<List<BattleChatEntry>>.empty();
    }
  }

  Future<AppResult<void>> sendChatMessage({
    required String battleId,
    required String userId,
    required String userName,
    required String message,
  }) async {
    final bid = battleId.trim();
    final uid = userId.trim();
    final text = message.trim();
    if (bid.isEmpty || uid.isEmpty || text.isEmpty) {
      return const AppFailure();
    }

    try {
      await _supabase.from('battle_chat').insert(<String, dynamic>{
        'battle_id': bid,
        'user_id': uid,
        'user_name': userName.trim(),
        'message': text,
      });
      return const AppSuccess(null);
    } catch (e) {
      developer.log('sendChatMessage failed', name: 'WEAFRICA.Live', error: e);
      return const AppFailure();
    }
  }

  Stream<List<BattleRequestEntry>> watchRequests({
    required String battleId,
    int limit = 20,
  }) {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      return const Stream<List<BattleRequestEntry>>.empty();
    }

    try {
      return _supabase
          .from('battle_requests')
          .stream(primaryKey: const ['id'])
          .eq('battle_id', bid)
          .order('created_at', ascending: true)
          .limit(limit)
          .asyncMap((rows) async {
            final base = rows
                .map((row) => BattleRequestEntry.fromRow(Map<String, dynamic>.from(row)))
                .toList(growable: false);

            final ids = base
                .map((entry) => entry.requesterId)
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList(growable: false);
            if (ids.isEmpty) return base;

            try {
              final profiles = await _supabase
                  .from('profiles')
                  .select('id, display_name, username, avatar_url')
                  .inFilter('id', ids);

              final byId = <String, Map<String, dynamic>>{};
              for (final raw in (profiles as List).whereType<Map>()) {
                final map = Map<String, dynamic>.from(raw);
                final id = (map['id'] ?? '').toString().trim();
                if (id.isEmpty) continue;
                byId[id] = map;
              }

              return base.map((entry) {
                final profile = byId[entry.requesterId];
                if (profile == null) return entry.copyWith(requesterName: entry.requesterId);

                final display = (profile['display_name'] ?? '').toString().trim();
                final username = (profile['username'] ?? '').toString().trim();
                final avatar = (profile['avatar_url'] ?? '').toString().trim();
                return entry.copyWith(
                  requesterName: display.isNotEmpty
                      ? display
                      : (username.isNotEmpty ? '@$username' : entry.requesterId),
                  avatarUrl: avatar.isEmpty ? null : avatar,
                );
              }).toList(growable: false);
            } catch (e) {
              developer.log('watchRequests profile lookup failed',
                  name: 'WEAFRICA.Live', error: e);
              return base;
            }
          });
    } catch (e) {
      developer.log('watchRequests failed', name: 'WEAFRICA.Live', error: e);
      return const Stream<List<BattleRequestEntry>>.empty();
    }
  }

  Stream<BattleVoteSummary> watchVoteSummary({
    required String battleId,
    required String competitor1Id,
    required String competitor2Id,
    required String currentUserId,
  }) {
    final bid = battleId.trim();
    final c1 = competitor1Id.trim();
    final c2 = competitor2Id.trim();
    if (bid.isEmpty || c1.isEmpty || c2.isEmpty) {
      return const Stream<BattleVoteSummary>.empty();
    }

    try {
      return _supabase
          .from('battle_votes')
          .stream(primaryKey: const ['id'])
          .eq('battle_id', bid)
          .order('created_at', ascending: false)
          .map((rows) {
            var votes1 = 0;
            var votes2 = 0;
            String? myVote;

            for (final row in rows) {
              final votedFor = (row['voted_for'] ?? '').toString().trim();
              final userId = (row['user_id'] ?? '').toString().trim();
              if (votedFor == c1) votes1 += 1;
              if (votedFor == c2) votes2 += 1;
              if (userId == currentUserId.trim()) {
                myVote = votedFor.isEmpty ? null : votedFor;
              }
            }

            return BattleVoteSummary(
              competitor1Id: c1,
              competitor2Id: c2,
              competitor1Votes: votes1,
              competitor2Votes: votes2,
              myVote: myVote,
            );
          });
    } catch (e) {
      developer.log('watchVoteSummary failed', name: 'WEAFRICA.Live', error: e);
      return const Stream<BattleVoteSummary>.empty();
    }
  }

  Future<AppResult<void>> addRequest({
    required String battleId,
    required String requesterId,
  }) async {
    final bid = battleId.trim();
    final rid = requesterId.trim();
    if (bid.isEmpty || rid.isEmpty) return const AppFailure();

    try {
      await _supabase.rpc('add_battle_request', params: <String, dynamic>{
        'p_battle_id': bid,
        'p_requester_id': rid,
      });
      return const AppSuccess(null);
    } catch (e) {
      developer.log('addRequest failed', name: 'WEAFRICA.Live', error: e);
      return const AppFailure();
    }
  }

  Future<AppResult<void>> castVote({
    required String battleId,
    required String userId,
    required String votedFor,
  }) async {
    final bid = battleId.trim();
    final uid = userId.trim();
    final target = votedFor.trim();
    if (bid.isEmpty || uid.isEmpty || target.isEmpty) return const AppFailure();

    try {
      final bearer = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
      if (bearer.isNotEmpty) {
        final uri = _uriBuilder.build('/api/battle/vote');
        final res = await http
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
                'Authorization': 'Bearer $bearer',
              },
              body: jsonEncode(<String, Object?>{
                'battle_id': bid,
                'voted_for': target,
              }),
            )
            .timeout(_requestTimeout);

        final decoded = _decodeMap(res.body);
        if (res.statusCode >= 200 && res.statusCode < 300 && decoded?['ok'] == true) {
          return const AppSuccess(null);
        }
      }

      await _supabase.rpc('add_vote', params: <String, dynamic>{
        'p_battle_id': bid,
        'p_user_id': uid,
        'p_voted_for': target,
      });
      return const AppSuccess(null);
    } catch (e) {
      developer.log('castVote failed', name: 'WEAFRICA.Live', error: e);
      return const AppFailure();
    }
  }

  Future<AppResult<AcceptedBattleRequest>> acceptNextRequest({
    required String battleId,
  }) async {
    final bid = battleId.trim();
    if (bid.isEmpty) return const AppFailure();

    try {
      final result = await _supabase.rpc(
        'accept_next_request',
        params: <String, dynamic>{'p_battle_id': bid},
      );

      final row = _coerceSingleRow(result);
      if (row == null) return const AppFailure();

      final requesterId = (row['requester_id'] ?? '').toString().trim();
      final requestId = (row['request_id'] ?? '').toString().trim();
      if (requesterId.isEmpty || requestId.isEmpty) return const AppFailure();

      return AppSuccess(
        AcceptedBattleRequest(requestId: requestId, requesterId: requesterId),
      );
    } catch (e) {
      developer.log('acceptNextRequest failed', name: 'WEAFRICA.Live', error: e);
      return const AppFailure();
    }
  }

  Future<AppResult<void>> rejectRequest({
    required String requestId,
  }) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return const AppFailure();

    try {
      await _supabase.rpc('reject_battle_request', params: <String, dynamic>{
        'p_request_id': rid,
      });
      return const AppSuccess(null);
    } catch (e) {
      developer.log('rejectRequest failed', name: 'WEAFRICA.Live', error: e);
      return const AppFailure();
    }
  }

  Map<String, dynamic>? _coerceSingleRow(dynamic result) {
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }
}