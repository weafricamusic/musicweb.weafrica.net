import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/config/app_env.dart';
import '../../../app/network/api_uri_builder.dart';
import 'live_session_exceptions.dart';

class LiveSessionsApi {
  const LiveSessionsApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

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

  Future<void> startSession({
    required String channelId,
    required String idToken,
    String? hostName,
    String? title,
    String? category,
    String? liveType,
    String? mode,
    String? thumbnailUrl,
    String? topic,
    String? accessMode,
  }) async {
    final uri = _uriBuilder.build('/api/live/sessions/start');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${idToken.trim()}',
    };

    if (!kReleaseMode) {
      final testToken = AppEnv.testToken.trim();
      if (testToken.isNotEmpty) {
        headers['x-weafrica-test-token'] = testToken;
      }
    }

    final payload = <String, Object?>{
      'channel_id': channelId,
      if ((hostName ?? '').trim().isNotEmpty) 'host_name': hostName!.trim(),
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
      if ((liveType ?? '').trim().isNotEmpty) 'live_type': liveType!.trim(),
      if ((mode ?? '').trim().isNotEmpty) 'mode': mode!.trim(),
      if ((thumbnailUrl ?? '').trim().isNotEmpty) 'thumbnail_url': thumbnailUrl!.trim(),
      if ((topic ?? '').trim().isNotEmpty) 'topic': topic!.trim(),
      if ((accessMode ?? '').trim().isNotEmpty) 'access_mode': accessMode!.trim(),
    };

    final res = await http
      .post(uri, headers: headers, body: jsonEncode(payload))
      .timeout(const Duration(seconds: 20));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      if (res.statusCode == 409) {
        throw LiveSessionConflictException(
          msg.isNotEmpty ? msg : 'You are already live. End your current stream first.',
        );
      }
      throw Exception(
        msg.isNotEmpty ? msg : 'Failed to start live session. Please try again.',
      );
    }
  }

  Future<void> heartbeat({
    required String channelId,
    required String idToken,
  }) async {
    final uri = _uriBuilder.build('/api/live/sessions/heartbeat');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${idToken.trim()}',
    };

    if (!kReleaseMode) {
      final testToken = AppEnv.testToken.trim();
      if (testToken.isNotEmpty) {
        headers['x-weafrica-test-token'] = testToken;
      }
    }

    final res = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'channel_id': channelId.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw Exception(
        msg.isNotEmpty ? msg : 'Failed to keep live session active. Please try again.',
      );
    }
  }

  Future<void> endSession({
    required String channelId,
    required String idToken,
  }) async {
    final uri = _uriBuilder.build('/api/live/sessions/end');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${idToken.trim()}',
    };

    if (!kReleaseMode) {
      final testToken = AppEnv.testToken.trim();
      if (testToken.isNotEmpty) {
        headers['x-weafrica-test-token'] = testToken;
      }
    }

    final res = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'channel_id': channelId.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _messageFromBody(res.body);
      throw Exception(
        msg.isNotEmpty ? msg : 'Failed to end live session. Please try again.',
      );
    }
  }
}
