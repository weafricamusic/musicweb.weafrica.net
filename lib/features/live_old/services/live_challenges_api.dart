import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/stream_challenge.dart';

class LiveChallengesApi {
  LiveChallengesApi({
    ApiUriBuilder? uriBuilder,
    FirebaseAuth? auth,
  })  : _uriBuilder = uriBuilder ?? const ApiUriBuilder(),
        _auth = auth ?? FirebaseAuth.instance;

  final ApiUriBuilder _uriBuilder;
  final FirebaseAuth _auth;
  static const Duration _timeout = Duration(seconds: 20);

  void _requireSignedInUser() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Not signed in (missing Firebase ID token).');
    }
  }

  Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  String _messageFromBody(String body) {
    final map = _decodeJsonMap(body);
    return (map?['message'] ?? map?['error_description'] ?? map?['error'] ?? '').toString().trim();
  }

  StreamChallenge _challengeFromInvite(Map<String, dynamic> invite) {
    final metadata = <String, dynamic>{};
    final fromProfile = invite['from_profile'];
    if (fromProfile is Map) {
      final profile = fromProfile.map((k, v) => MapEntry(k.toString(), v));
      final name = (profile['display_name'] ?? profile['username'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        metadata['message'] = '$name invited you to a battle';
      }
    }

    final challengeMap = <String, dynamic>{
      'id': (invite['id'] ?? '').toString(),
      'challenger_id': (invite['from_uid'] ?? '').toString(),
      'target_id': (invite['to_uid'] ?? '').toString(),
      'live_room_id': (invite['channel_id'] ?? invite['battle_id'] ?? '').toString(),
      'status': (invite['status'] ?? 'pending').toString(),
      'metadata': metadata,
      'created_at': invite['created_at'],
      'expires_at': invite['expires_at'],
      'challenger': invite['from_profile'],
      'target': invite['to_profile'],
    };

    return StreamChallenge.fromMap(challengeMap);
  }

  /// Calls API backend: POST /api/battle/invite/create
  Future<StreamChallenge> sendChallenge({
    required String targetUserId,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    final target = targetUserId.trim();
    if (target.isEmpty) {
      throw ArgumentError('targetUserId is required');
    }

    _requireSignedInUser();
    final uri = _uriBuilder.build('/api/battle/invite/create');

    final coinGoalRaw = metadata?['betAmount'];
    final coinGoal = coinGoalRaw is num
        ? coinGoalRaw.toInt()
        : int.tryParse((coinGoalRaw ?? '').toString().trim()) ?? 1000;

    final beatNameRaw = (metadata?['beatName'] ?? metadata?['beat_name'] ?? '').toString().trim();
    final beatName = beatNameRaw.isEmpty ? 'Challenge Beat' : beatNameRaw;

    final payload = <String, Object?>{
      'to_uid': target,
      'ttl_seconds': 300,
      'battle': {
        'title': 'Challenge Battle',
        'category': 'Battle',
        'duration_seconds': 300,
        'battle_type': 'artist',
        'beat_name': beatName,
        'coin_goal': coinGoal,
        'country': 'Malawi',
        'access_mode': 'free',
        'price_coins': 0,
        'gift_enabled': true,
        'voting_enabled': true,
        'battle_format': 'continuous',
        'round_count': 1,
      },
      if ((message ?? '').trim().isNotEmpty || (metadata != null && metadata.isNotEmpty))
        'meta': {
          if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw StateError(
        'Failed to send challenge (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    final decoded = _decodeJsonMap(res.body);
    final raw = decoded?['invite'] ?? decoded;
    if (raw is Map) {
      final m = raw.map((k, v) => MapEntry(k.toString(), v));
      return _challengeFromInvite(Map<String, dynamic>.from(m));
    }

    throw StateError('Invalid challenge response from server.');
  }

  /// Calls API backend: POST /api/battle/invite/respond
  Future<Map<String, dynamic>> acceptChallenge({
    required String challengeId,
  }) async {
    final cid = challengeId.trim();
    if (cid.isEmpty) {
      throw ArgumentError('challengeId is required');
    }

    _requireSignedInUser();
    final uri = _uriBuilder.build('/api/battle/invite/respond');

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'invite_id': cid,
        'action': 'accept',
      }),
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw StateError(
        'Failed to accept challenge (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null) {
      throw StateError('Invalid accept challenge response shape');
    }
    return decoded;
  }

  /// Calls API backend: GET /api/battle/invites?box=inbox&status=pending
  Future<List<StreamChallenge>> listPendingChallenges() async {
    _requireSignedInUser();
    final uri = _uriBuilder.build(
      '/api/battle/invites',
      queryParameters: <String, String>{
        'box': 'inbox',
        'status': 'pending',
      },
    );

    if (kDebugMode) {
      debugPrint('🌐 LiveChallengesApi.listPendingChallenges GET $uri');
    }

    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
      },
      timeout: _timeout,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw StateError(
        'Failed to fetch pending challenges (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    final decoded = jsonDecode(res.body);

    final raw = (decoded is Map) ? (decoded['invites'] ?? decoded['challenges'] ?? decoded['data']) : decoded;
    if (raw is! List) {
      throw StateError('Invalid pending challenges response shape');
    }

    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => _challengeFromInvite(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }
}
