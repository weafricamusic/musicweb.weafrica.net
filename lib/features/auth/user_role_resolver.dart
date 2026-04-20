import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';

import 'user_role.dart';

class UserRoleResolver {
  static Future<UserRole> resolveCurrentUser({SupabaseClient? client}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return UserRole.consumer;
    return resolveForFirebaseUid(user.uid, client: client);
  }

  static Future<UserRole> resolveForFirebaseUid(
    String firebaseUid, {
    SupabaseClient? client,
  }) async {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) return UserRole.consumer;

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/auth/role');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
      timeout: const Duration(seconds: 8),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Role resolution failed (HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw StateError('Role resolution returned invalid payload');
    }

    final role = decoded['role']?.toString();
    return UserRoleX.fromId(role);
  }
}
