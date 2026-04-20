import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';

import 'user_role.dart';

class CreatorProfileProvisioner {
  static Future<String?> ensureArtistIdForCurrentUser({SupabaseClient? client}) async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final uid = user.uid.trim();
    if (uid.isEmpty) return null;

    final displayName = _bestDisplayName(user);
    final email = (user.email ?? '').trim();

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/auth/provision-creator');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'intent': UserRole.artist.id,
        'display_name': displayName,
        if (email.isNotEmpty) 'email': email,
      }),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Creator provisioning failed (HTTP ${res.statusCode}): ${res.body}');
    }

    if (res.body.trim().isEmpty) {
      throw StateError('Creator provisioning returned an empty response body');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Creator provisioning returned an invalid JSON payload');
    }

    final id = decoded['artist_id'];
    if (id is String && id.trim().isNotEmpty) return id.trim();

    throw StateError('Creator provisioning succeeded but artist_id was missing');
  }

  static Future<void> ensureForCurrentUser({
    required UserRole intent,
    SupabaseClient? client,
  }) async {
    if (intent == UserRole.consumer) return;

    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    if (uid.trim().isEmpty) return;

    final displayName = _bestDisplayName(user);
    final email = (user.email ?? '').trim();

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/auth/provision-creator');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'intent': intent.id,
        'display_name': displayName,
        if (email.isNotEmpty) 'email': email,
      }),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Creator provisioning failed (HTTP ${res.statusCode}): ${res.body}');
    }
  }

  static String _bestDisplayName(fb_auth.User user) {
    final fromDisplayName = (user.displayName ?? '').trim();
    if (fromDisplayName.isNotEmpty) return fromDisplayName;

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      if (at > 0) return email.substring(0, at);
      return email;
    }

    final uid = user.uid;
    if (uid.length <= 8) return uid;
    return '${uid.substring(0, 4)}…${uid.substring(uid.length - 4)}';
  }
}
