import 'dart:async';
import 'dart:convert';

import '../config/api_env.dart';
import 'firebase_authed_http.dart';

class ApiJsonResponse {
  const ApiJsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;
}

class WeAfricaApi {
  const WeAfricaApi._();

  static Uri _uri(String path) {
    final trimmed = path.trim();
    final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return Uri.parse('${ApiEnv.baseUrl}$normalized');
  }

  static Future<ApiJsonResponse> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 8),
    bool requireAuth = true,
  }) async {
    final uri = _uri(path);

    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
      timeout: timeout,
      requireAuth: requireAuth,
      includeAuthIfAvailable: requireAuth,
    );

    final raw = res.body.trim();
    if (raw.isEmpty) {
      return ApiJsonResponse(statusCode: res.statusCode, body: const <String, dynamic>{});
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return ApiJsonResponse(
        statusCode: res.statusCode,
        body: decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    throw FormatException('Expected JSON object from $uri');
  }

  static Future<ApiJsonResponse> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 10),
    bool requireAuth = true,
  }) async {
    final uri = _uri(path);

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body ?? const <String, dynamic>{}),
      timeout: timeout,
      requireAuth: requireAuth,
      includeAuthIfAvailable: requireAuth,
    );

    final raw = res.body.trim();
    if (raw.isEmpty) {
      return ApiJsonResponse(statusCode: res.statusCode, body: const <String, dynamic>{});
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return ApiJsonResponse(
        statusCode: res.statusCode,
        body: decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    throw FormatException('Expected JSON object from $uri');
  }
}
