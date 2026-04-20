import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';

import 'user_role.dart';

class UserProfileProvisioner {
  static Future<({bool ok, String? message})> provisionForCurrentUser({
    required UserRole intent,
    String? username,
    String? displayName,
    String? countryCode,
  }) async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return (ok: false, message: 'Not signed in');

    final uid = user.uid.trim();
    if (uid.isEmpty) return (ok: false, message: 'Missing user id');

    final email = (user.email ?? '').trim();
    final currentDisplayName = (user.displayName ?? '').trim();
    final name = (displayName ?? '').trim();

    try {
      final uri = Uri.parse('${ApiEnv.baseUrl}/api/auth/provision-profile');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'role': intent.id,
          if (name.isNotEmpty) 'display_name': name,
          if (name.isEmpty && currentDisplayName.isNotEmpty) 'display_name': currentDisplayName,
          if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
          if (email.isNotEmpty) 'email': email,
          if (countryCode != null && countryCode.trim().isNotEmpty) 'country_code': countryCode.trim(),
        }),
        timeout: const Duration(seconds: 10),
        requireAuth: true,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return (ok: true, message: null);
      }

      String? backendMsg;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          backendMsg = (decoded['message'] ?? decoded['error'] ?? decoded['code'])?.toString();
        }
      } catch (_) {
        // ignore
      }

      if (kDebugMode) {
        final m = (backendMsg ?? '').trim();
        final preview = m.length <= 200 ? m : '${m.substring(0, 200)}…';
        debugPrint(
          'UserProfileProvisioner: provision-profile failed (HTTP ${res.statusCode})'
          '${preview.isEmpty ? '' : ': $preview'}',
        );
      }

      // Never return raw backend details. Keep messages generic for users.
      if (res.statusCode == 401 || res.statusCode == 403) {
        return (ok: false, message: 'Please sign in and try again.');
      }
      return (ok: false, message: 'Could not set up your profile. Please try again.');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('UserProfileProvisioner: provision-profile call failed: $e');
        debugPrintStack(stackTrace: st, maxFrames: 40);
      }
      return (ok: false, message: 'Could not set up your profile. Please try again.');
    }
  }

  static Future<void> ensureForCurrentUser({
    required UserRole intent,
  }) async {
    final res = await provisionForCurrentUser(intent: intent);
    if (!res.ok) {
      if (kDebugMode) {
        debugPrint('UserProfileProvisioner: provision-profile failed: ${res.message}');
      }
      throw StateError(res.message ?? 'Could not set up your profile.');
    }
  }
}
