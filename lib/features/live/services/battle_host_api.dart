import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/network/firebase_authed_http.dart';
import '../../../app/network/api_uri_builder.dart';

class HostedBattle {
  const HostedBattle({
    required this.battleId,
    required this.channelId,
    required this.status,
  });

  final String battleId;
  final String channelId;
  final String status;
}

class BattleHostApi {
  const BattleHostApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  static const Duration _timeout = Duration(seconds: 20);

  Future<http.Response> _postJsonAuth(Uri uri, {required Object body}) async {
    final startedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint('🌐 POST $uri (timeout=${_timeout.inSeconds}s)');
    }

    try {
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: body,
        timeout: _timeout,
        requireAuth: true,
      );

      if (kDebugMode) {
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        debugPrint('✅ POST $uri -> HTTP ${res.statusCode} (${elapsed}ms)');
      }
      return res;
    } on TimeoutException {
      if (kDebugMode) {
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        debugPrint('⏰ POST $uri timed out after ${elapsed}ms');
      }
      throw StateError('Could not reach live server (request timed out). Please try again.');
    } on SocketException catch (e) {
      if (kDebugMode) {
        debugPrint('🌐❌ POST $uri socket error: $e');
      }
      throw StateError('Network error while contacting live server. Check connection and try again.');
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
    final msg = (map?['message'] ?? map?['error_description'] ?? map?['error'] ?? '').toString().trim();
    return msg;
  }

  bool _isDuplicateChannelCreateError({
    required int statusCode,
    required String message,
  }) {
    if (statusCode < 500) return false;
    final m = message.trim().toLowerCase();
    return m.contains('live_battles_channel_idkey') ||
        (m.contains('duplicate key') && m.contains('channel_id'));
  }

  HostedBattle _parseHostedBattleFromBattlePayload(Map<String, dynamic> decoded) {
    final raw = decoded['battle'];
    if (raw is! Map) {
      throw StateError('Invalid battle response (missing battle).');
    }
    final battle = raw.map((k, v) => MapEntry(k.toString(), v));

    final battleId = (battle['battle_id'] ?? battle['battleId'] ?? '').toString().trim();
    final channelId = (battle['channel_id'] ?? battle['channelId'] ?? '').toString().trim();
    final status = (battle['status'] ?? '').toString().trim();

    if (battleId.isEmpty || channelId.isEmpty) {
      throw StateError('Invalid battle response (missing battle_id/channel_id).');
    }

    return HostedBattle(
      battleId: battleId,
      channelId: channelId,
      status: status.isNotEmpty ? status : 'waiting',
    );
  }

  HostedBattle _parseHostedBattleFromInvitePayload(Map<String, dynamic> decoded) {
    final raw = decoded['invite'];
    if (raw is! Map) {
      throw StateError('Invalid invite response (missing invite).');
    }
    final invite = raw.map((k, v) => MapEntry(k.toString(), v));

    final battleId = (invite['battle_id'] ?? invite['battleId'] ?? '').toString().trim();
    final channelId = (invite['channel_id'] ?? invite['channelId'] ?? '').toString().trim();

    if (battleId.isEmpty || channelId.isEmpty) {
      throw StateError('Invalid invite response (missing battle_id/channel_id).');
    }

    return HostedBattle(battleId: battleId, channelId: channelId, status: 'waiting');
  }

  Future<HostedBattle> createBattle({
    required String title,
    required String category,
    required String battleType,
    required String beatName,
    required int durationMinutes,
    required int coinGoal,
    required String country,
    String? opponentId,
    DateTime? scheduledAt,
    String? accessMode,
    int? priceCoins,
    bool? giftEnabled,
    bool? votingEnabled,
    String? battleFormat,
    int? roundCount,
  }) async {
    final trimmedBeatName = beatName.trim();
    if (trimmedBeatName.isEmpty) {
      throw StateError('beat_name is required');
    }

    final uri = _uriBuilder.build('/api/battle/create');

    if (kDebugMode) {
      debugPrint('🌐 BattleHostApi.createBattle POST $uri');
    }

    final payload = <String, Object?>{
      'title': title.trim(),
      'category': category.trim(),
      'battle_type': battleType.trim(),
      'beat_name': trimmedBeatName,
      'duration_minutes': durationMinutes,
      'coin_goal': coinGoal,
      'country': country.trim(),
      ...?((opponentId ?? '').trim().isNotEmpty ? {'opponent_id': opponentId!.trim()} : null),
      ...?(scheduledAt == null ? null : {'scheduled_at': scheduledAt.toUtc().toIso8601String()}),
      ...?((accessMode ?? '').trim().isNotEmpty ? {'access_mode': accessMode!.trim()} : null),
      ...?(priceCoins == null ? null : {'price_coins': priceCoins}),
      ...?(giftEnabled == null ? null : {'gift_enabled': giftEnabled}),
      ...?(votingEnabled == null ? null : {'voting_enabled': votingEnabled}),
      ...?((battleFormat ?? '').trim().isNotEmpty ? {'battle_format': battleFormat!.trim()} : null),
      ...?(roundCount == null ? null : {'round_count': roundCount}),
    };

    for (var attempt = 0; attempt < 2; attempt++) {
      final res = await _postJsonAuth(uri, body: jsonEncode(payload));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = _decodeJsonMap(res.body);
        if (decoded == null || decoded['ok'] != true) {
          throw StateError('Battle create failed (invalid response).');
        }
        return _parseHostedBattleFromBattlePayload(decoded);
      }

      final msg = _messageFromBody(res.body);
      final canRetry = attempt == 0 &&
          _isDuplicateChannelCreateError(statusCode: res.statusCode, message: msg);
      if (canRetry) {
        if (kDebugMode) {
          debugPrint('🔁 BattleHostApi.createBattle retrying after duplicate channel error');
        }
        continue;
      }

      throw StateError(
        'Failed to create battle (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    throw StateError('Battle create failed after retry.');
  }

  Future<HostedBattle> createBattleAndInviteOpponent({
    required String toUid,
    required String title,
    required String category,
    required String battleType,
    required String beatName,
    required int durationMinutes,
    required int coinGoal,
    required String country,
    int ttlSeconds = 300,
  }) async {
    final trimmedBeatName = beatName.trim();
    if (trimmedBeatName.isEmpty) {
      throw StateError('beat_name is required');
    }

    final uri = _uriBuilder.build('/api/battle/invite/create');

    if (kDebugMode) {
      debugPrint('🌐 BattleHostApi.createBattleAndInviteOpponent POST $uri');
    }

    final durationSeconds = durationMinutes * 60;

    final payload = <String, Object?>{
      'to_uid': toUid.trim(),
      'ttl_seconds': ttlSeconds,
      'battle': {
        'title': title.trim(),
        'category': category.trim(),
        'duration_seconds': durationSeconds,
        'battle_type': battleType.trim(),
        'beat_name': trimmedBeatName,
        'coin_goal': coinGoal,
        'country': country.trim(),
        'access_mode': 'free',
        'price_coins': 0,
        'gift_enabled': true,
        'voting_enabled': true,
        'battle_format': 'continuous',
        'round_count': 0,
      },
    };

    final res = await _postJsonAuth(uri, body: jsonEncode(payload));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw StateError(
        'Failed to invite opponent (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null || decoded['ok'] != true) {
      throw StateError('Battle invite failed (invalid response).');
    }

    return _parseHostedBattleFromInvitePayload(decoded);
  }

  Future<void> sendInviteToExistingBattle({
    required String battleId,
    required String toUid,
    int ttlSeconds = 300,
  }) async {
    final bid = battleId.trim();
    final to = toUid.trim();
    if (bid.isEmpty || to.isEmpty) return;

    final uri = _uriBuilder.build('/api/battle/invite/send');
    final payload = <String, Object?>{
      'battle_id': bid,
      'to_uid': to,
      'ttl_seconds': ttlSeconds,
    };

    if (kDebugMode) {
      debugPrint('🌐 BattleHostApi.sendInviteToExistingBattle POST $uri');
      debugPrint('📨 battle_id=$bid to_uid=$to ttl=$ttlSeconds');
    }

    final res = await _postJsonAuth(uri, body: jsonEncode(payload));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      if (kDebugMode) {
        debugPrint('❌ /api/battle/invite/send failed status=${res.statusCode} body=${res.body}');
      }
      throw StateError(
        'Failed to invite opponent (HTTP ${res.statusCode}).'
        '${msg.isNotEmpty ? ' $msg' : ''}',
      );
    }

    if (kDebugMode) {
      debugPrint('✅ /api/battle/invite/send success status=${res.statusCode} body=${res.body}');
    }
  }
}
