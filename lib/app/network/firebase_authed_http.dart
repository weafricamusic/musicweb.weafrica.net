import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';

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

    // Get Firebase ID token
    String? token;
    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        token = await user.getIdToken(forceRefresh);
        if (kDebugMode) {
          debugPrint('🔑 Firebase token obtained: ${token != null ? "Yes (${token.length} chars)" : "No"}');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ No Firebase user logged in');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get Firebase token: $e');
      }
    }

    if (token != null && token.isNotEmpty) {
      merged['Authorization'] = 'Bearer $token';
    } else if (requireAuth) {
      throw Exception('Authentication required but no token available');
    }

    return merged;
  }
}
