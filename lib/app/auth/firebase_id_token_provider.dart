import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

class FirebaseIdTokenProvider {
  const FirebaseIdTokenProvider._();

  static const Duration _tokenTimeout = Duration(seconds: 12);
  static const Duration _retryDelay = Duration(milliseconds: 700);

  static bool _isNetworkAuthError(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseAuthException) {
      final code = error.code.toLowerCase();
      if (code == 'network-request-failed') return true;
      final msg = (error.message ?? '').toLowerCase();
      return msg.contains('network') || msg.contains('timeout');
    }
    return false;
  }

  static bool _isSecureTokenRouteFailure(Object error) {
    if (error is! FirebaseAuthException) return false;
    final msg = (error.message ?? '').toLowerCase();
    if (!msg.contains('securetoken.googleapis.com')) return false;
    return msg.contains('failed to connect') ||
        msg.contains('connection refused') ||
        msg.contains('/192.168.') ||
        msg.contains('/10.') ||
        msg.contains('/172.16.') ||
        msg.contains('/172.17.') ||
        msg.contains('/172.18.') ||
        msg.contains('/172.19.') ||
        msg.contains('/172.2') ||
        msg.contains('/172.3');
  }

  static Future<String?> _getToken(User user, {required bool forceRefresh}) async {
    try {
      return await user.getIdToken(forceRefresh).timeout(_tokenTimeout);
    } on TimeoutException {
      throw StateError('Timed out while fetching sign-in token. Please check your connection and try again.');
    }
  }

  static Future<String?> _getTokenWithRetry(
    User user, {
    required bool forceRefresh,
  }) async {
    try {
      return await _getToken(user, forceRefresh: forceRefresh);
    } catch (e) {
      if (!_isNetworkAuthError(e)) rethrow;
      await Future<void>.delayed(_retryDelay);
      // Retry with force refresh to recover from transient stale token/network states.
      return _getToken(user, forceRefresh: true);
    }
  }

  /// Returns a trimmed Firebase ID token if the user is signed in.
  ///
  /// - If [forceRefresh] is true, fetches a fresh token from Firebase.
  /// - If the non-forced token is missing/empty but a user exists, it will
  ///   attempt a forced refresh once.
  static Future<String?> maybe({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    String? token;
    try {
      token = await _getTokenWithRetry(user, forceRefresh: forceRefresh);
    } on FirebaseAuthException catch (e) {
      if (_isSecureTokenRouteFailure(e)) {
        throw StateError(
          'Sign-in token could not be fetched because securetoken.googleapis.com is unreachable from this network. '
          'Disable VPN/proxy/private DNS, switch Wi-Fi/mobile data, and ensure date/time are automatic.',
        );
      }
      // Surface a more actionable message to the UI.
      final code = e.code.toLowerCase();
      if (code == 'network-request-failed' || (e.message ?? '').toLowerCase().contains('network')) {
        throw StateError(
          'Firebase Auth network request failed. Check internet access, disable VPN/proxy if enabled, and verify device date/time.',
        );
      }
      rethrow;
    }
    final trimmed = token?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;

    if (!forceRefresh) {
      String? refreshed;
      try {
        refreshed = await _getTokenWithRetry(user, forceRefresh: true);
      } on FirebaseAuthException catch (e) {
        if (_isSecureTokenRouteFailure(e)) {
          throw StateError(
            'Sign-in token could not be refreshed because securetoken.googleapis.com is unreachable from this network. '
            'Disable VPN/proxy/private DNS, switch Wi-Fi/mobile data, and ensure date/time are automatic.',
          );
        }
        final code = e.code.toLowerCase();
        if (code == 'network-request-failed' || (e.message ?? '').toLowerCase().contains('network')) {
          throw StateError(
            'Firebase Auth network request failed. Check internet access, disable VPN/proxy if enabled, and verify device date/time.',
          );
        }
        rethrow;
      }
      final refreshedTrimmed = refreshed?.trim();
      if (refreshedTrimmed != null && refreshedTrimmed.isNotEmpty) {
        return refreshedTrimmed;
      }
    }

    return null;
  }

  /// Returns a Firebase ID token or throws if the user is not signed in.
  static Future<String> require({bool forceRefresh = false}) async {
    final token = await maybe(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('Not signed in (missing Firebase ID token).');
    }
    return token;
  }
}
