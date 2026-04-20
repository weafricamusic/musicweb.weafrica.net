import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// import '../auth/firebase_idtoken_provider.dart';

class FirebaseAuthedHttp {
  const FirebaseAuthedHttp._();

  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
    bool includeAuthIfAvailable = true,
    bool requireAuth = false,
  }) async {
    final initialHeaders = await _buildHeaders(
      headers,
      includeAuthIfAvailable: includeAuthIfAvailable,
      requireAuth: requireAuth,
      forceRefresh: false,
    );

    http.Response res = await http.get(uri, headers: initialHeaders).timeout(timeout);

    if (_isAuthFailure(res.statusCode) && (includeAuthIfAvailable || requireAuth)) {
      final refreshedHeaders = await _buildHeaders(
        headers,
        includeAuthIfAvailable: includeAuthIfAvailable,
        requireAuth: requireAuth,
        forceRefresh: true,
      );

      // Retry only if we can actually provide auth now.
      if (refreshedHeaders.containsKey('Authorization')) {
        res = await http.get(uri, headers: refreshedHeaders).timeout(timeout);
      }
    }

    return res;
  }

  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 5),
    bool includeAuthIfAvailable = true,
    bool requireAuth = false,
  }) async {
    final initialHeaders = await _buildHeaders(
      headers,
      includeAuthIfAvailable: includeAuthIfAvailable,
      requireAuth: requireAuth,
      forceRefresh: false,
    );

    http.Response res = await http
        .post(uri, headers: initialHeaders, body: body, encoding: encoding)
        .timeout(timeout);

    if (_isAuthFailure(res.statusCode) && (includeAuthIfAvailable || requireAuth)) {
      final refreshedHeaders = await _buildHeaders(
        headers,
        includeAuthIfAvailable: includeAuthIfAvailable,
        requireAuth: requireAuth,
        forceRefresh: true,
      );

      if (refreshedHeaders.containsKey('Authorization')) {
        res = await http
            .post(uri, headers: refreshedHeaders, body: body, encoding: encoding)
            .timeout(timeout);
      }
    }

    return res;
  }

  static Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 5),
    bool includeAuthIfAvailable = true,
    bool requireAuth = false,
  }) async {
    final initialHeaders = await _buildHeaders(
      headers,
      includeAuthIfAvailable: includeAuthIfAvailable,
      requireAuth: requireAuth,
      forceRefresh: false,
    );

    http.Response res = await http
        .put(uri, headers: initialHeaders, body: body, encoding: encoding)
        .timeout(timeout);

    if (_isAuthFailure(res.statusCode) && (includeAuthIfAvailable || requireAuth)) {
      final refreshedHeaders = await _buildHeaders(
        headers,
        includeAuthIfAvailable: includeAuthIfAvailable,
        requireAuth: requireAuth,
        forceRefresh: true,
      );

      if (refreshedHeaders.containsKey('Authorization')) {
        res = await http
            .put(uri, headers: refreshedHeaders, body: body, encoding: encoding)
            .timeout(timeout);
      }
    }

    return res;
  }

  static Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 5),
    bool includeAuthIfAvailable = true,
    bool requireAuth = false,
  }) async {
    final initialHeaders = await _buildHeaders(
      headers,
      includeAuthIfAvailable: includeAuthIfAvailable,
      requireAuth: requireAuth,
      forceRefresh: false,
    );

    http.Response res = await http
        .delete(uri, headers: initialHeaders, body: body, encoding: encoding)
        .timeout(timeout);

    if (_isAuthFailure(res.statusCode) && (includeAuthIfAvailable || requireAuth)) {
      final refreshedHeaders = await _buildHeaders(
        headers,
        includeAuthIfAvailable: includeAuthIfAvailable,
        requireAuth: requireAuth,
        forceRefresh: true,
      );

      if (refreshedHeaders.containsKey('Authorization')) {
        res = await http
            .delete(uri, headers: refreshedHeaders, body: body, encoding: encoding)
            .timeout(timeout);
      }
    }

    return res;
  }

  static bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;

  static Future<Map<String, String>> _buildHeaders(
    Map<String, String>? base, {
    required bool includeAuthIfAvailable,
    required bool requireAuth,
    required bool forceRefresh,
  }) async {
    final merged = <String, String>{
      if (base != null) ...base,
    };

    if (!includeAuthIfAvailable && !requireAuth) return merged;

    // Firebase ID token provider currently disabled in this environment.
    final String? token = null;

    if (token != null && token.isNotEmpty) {
      merged['Authorization'] = 'Bearer $token';
    }

    return merged;
  }
}
