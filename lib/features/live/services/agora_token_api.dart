import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/config/app_env.dart';
import '../../../app/network/api_uri_builder.dart';

enum AgoraRtcRole { broadcaster, audience }

class AgoraTokenApi {
  const AgoraTokenApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('Invalid Agora token response shape');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<String> fetchRtcToken({
    required String channelId,
    required AgoraRtcRole role,
    required int uid,
    String? idToken,
    String? battleId,
    int ttlSeconds = 3600,
  }) async {
    final uri = _uriBuilder.build('/api/agora/token');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };

    final bearer = (idToken ?? '').trim();
    if (bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }

    // Non-battle broadcaster tokens can be minted with test access in debug.
    // Keep this compatible with the diagnostics flow.
    if (!kReleaseMode && (headers['Authorization']?.isEmpty ?? true)) {
      final testToken = AppEnv.testToken.trim();
      if (testToken.isNotEmpty) {
        headers['x-weafrica-test-token'] = testToken;
      }
    }

    final payload = <String, Object?>{
      'channel_id': channelId,
      'role': role == AgoraRtcRole.broadcaster ? 'broadcaster' : 'audience',
      'uid': uid,
      'ttl_seconds': ttlSeconds,
      if ((battleId ?? '').trim().isNotEmpty) 'battle_id': battleId!.trim(),
    };

    final res = await http
      .post(uri, headers: headers, body: jsonEncode(payload))
      .timeout(const Duration(seconds: 20));

    final decoded = _decodeJsonMap(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
      throw StateError(
        msg.isNotEmpty
            ? 'Agora token API failed (HTTP ${res.statusCode}): $msg'
            : 'Agora token API failed (HTTP ${res.statusCode}).',
      );
    }

    if (kDebugMode) {
      final mintedAppId = (decoded['app_id'] ?? '').toString().trim();
      final mintedChannelId = (decoded['channel_id'] ?? '').toString().trim();
      final mintedUid = int.tryParse((decoded['uid'] ?? '').toString().trim());
      final mintedRole = (decoded['role'] ?? '').toString().trim();

      final localAppId = AppEnv.agoraAppId.trim();
      if (mintedAppId.isNotEmpty && localAppId.isNotEmpty && mintedAppId != localAppId) {
        debugPrint('📹⚠️ Agora token app_id mismatch minted=$mintedAppId local=$localAppId');
      }
      if (mintedChannelId.isNotEmpty && mintedChannelId != channelId.trim()) {
        debugPrint('📹⚠️ Agora token channel mismatch minted=$mintedChannelId requested=${channelId.trim()}');
      }
      if (mintedUid != null && mintedUid != uid) {
        debugPrint('📹⚠️ Agora token uid mismatch minted=$mintedUid requested=$uid');
      }
      if (mintedRole.isNotEmpty) {
        debugPrint('📹 Agora token role=$mintedRole uid=${mintedUid ?? uid} channel=$mintedChannelId');
      }
    }

    final token = (decoded['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw StateError('Agora token API returned an empty token.');
    }

    return token;
  }

  Future<String> fetchRtmToken({
    String? idToken,
    int ttlSeconds = 3600,
    String? userIdOverride,
  }) async {
    final uri = _uriBuilder.build('/api/agora/rtm/token');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };

    final bearer = (idToken ?? '').trim();
    if (bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }

    if (!kReleaseMode && (headers['Authorization']?.isEmpty ?? true)) {
      final testToken = AppEnv.testToken.trim();
      if (testToken.isNotEmpty) {
        headers['x-weafrica-test-token'] = testToken;
      }
    }

    final normalizedTtl = ttlSeconds < 60
        ? 60
        : ttlSeconds > 24 * 3600
            ? 24 * 3600
            : ttlSeconds;

    final payload = <String, Object?>{
      'ttl_seconds': normalizedTtl,
    };

    final override = (userIdOverride ?? '').trim();
    if (override.isNotEmpty) {
      payload['user_id'] = override;
    }

    final res = await http
      .post(uri, headers: headers, body: jsonEncode(payload))
      .timeout(const Duration(seconds: 20));

    final decoded = _decodeJsonMap(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
      throw StateError(
        msg.isNotEmpty
            ? 'Agora RTM token API failed (HTTP ${res.statusCode}): $msg'
            : 'Agora RTM token API failed (HTTP ${res.statusCode}).',
      );
    }

    final token = (decoded['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw StateError('Agora RTM token API returned an empty token.');
    }

    return token;
  }
}
