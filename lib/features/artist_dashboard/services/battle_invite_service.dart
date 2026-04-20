import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../battle/battle_models.dart';
import '../../live/models/battle_invite.dart';

class ProfileMatch {
  const ProfileMatch({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.role,
  });

  final String uid;
  final String username;
  final String displayName;
  final String role;

  String get handle => username.isEmpty ? displayName : '@$username';
}

class BattleInviteService {
  const BattleInviteService({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Future<ProfileMatch?> resolveOpponent(String rawHandle) async {
    final trimmed = rawHandle.trim();
    if (trimmed.isEmpty) return null;

    final query = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    if (query.isEmpty) return null;

    final uri = _uriBuilder.build(
      '/api/profiles/search',
      queryParameters: <String, String>{
        'q': query,
        'limit': '8',
      },
    );

    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
      timeout: const Duration(seconds: 10),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Profile search failed (${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;

    final profiles = decoded['profiles'];
    if (profiles is! List) return null;

    final candidates = <ProfileMatch>[];
    for (final raw in profiles) {
      if (raw is! Map) continue;
      final uid = (raw['id'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      final username = (raw['username'] ?? '').toString().trim();
      final displayName = (raw['display_name'] ?? raw['displayName'] ?? '').toString().trim();
      final role = (raw['role'] ?? '').toString().trim();
      candidates.add(
        ProfileMatch(
          uid: uid,
          username: username,
          displayName: displayName.isEmpty ? username : displayName,
          role: role,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    final normalized = query.toLowerCase();
    for (final c in candidates) {
      if (c.username.toLowerCase() == normalized) return c;
    }

    for (final c in candidates) {
      if (c.displayName.toLowerCase() == normalized) return c;
    }

    return candidates.first;
  }

  Future<BattleInvite> createInvite({
    required String toUid,
    required BattleDraft draft,
    required String opponentHandle,
    int ttlSeconds = 300,
  }) async {
    final safeHandle = opponentHandle.trim().isEmpty ? draft.opponent.trim() : opponentHandle.trim();
    final trackTitle = draft.track?.title.trim().isNotEmpty == true
        ? draft.track!.title.trim()
        : 'Battle';

    final title = '$trackTitle vs $safeHandle';

    final payload = <String, dynamic>{
      'to_uid': toUid,
      'ttl_seconds': ttlSeconds,
      'battle': {
        'title': title,
        'duration_seconds': 30 * 60,
        'access_mode': 'free',
        'price_coins': 0,
        'gift_enabled': true,
        'voting_enabled': true,
        'battle_format': 'continuous',
        'round_count': 0,
      },
    };

    final uri = _uriBuilder.build('/api/battle/invite/create');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Invite failed (${res.statusCode}).';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
        }
      } catch (_) {
        final raw = res.body.trim();
        if (raw.isNotEmpty) msg = raw;
      }
      throw Exception(msg);
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception('Invite response was not valid JSON.');
    }

    final inviteRaw = decoded['invite'];
    if (inviteRaw is Map) {
      final mapped = inviteRaw.map((k, v) => MapEntry(k.toString(), v));
      return BattleInvite.fromMap(Map<String, dynamic>.from(mapped));
    }

    throw Exception('Invite response missing invite data.');
  }

  Future<void> setReady({
    required String battleId,
    bool ready = true,
  }) async {
    final uri = _uriBuilder.build('/api/battle/ready');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'battle_id': battleId,
        'ready': ready,
      }),
      timeout: const Duration(seconds: 10),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('BattleInviteService.setReady failed (${res.statusCode}): ${res.body}');
      }
    }
  }
}
