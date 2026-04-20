import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_role.dart';

/// Stores what the user *intends* to sign in as (UI preference).
///
/// This is intentionally separate from [UserRoleStore], which persists the
/// *resolved* role for services like analytics/FCM.
class UserRoleIntentStore {
  static const String _key = 'weafrica_login_role_intent';

  /// Whether a role intent was explicitly saved in persistent storage.
  ///
  /// - `null`: not loaded yet
  /// - `false`: no value stored (first-run/default)
  /// - `true`: user explicitly selected a mode previously
  static bool? _hasExplicitValue;

  static bool get hasLoaded => _hasExplicitValue != null;
  static bool get hasExplicitValue => _hasExplicitValue == true;

  /// In-memory notifier for the current intent.
  ///
  /// This enables UI (like AppShell) to react immediately when the user
  /// switches between Listener / Artist / DJ modes.
  static final ValueNotifier<UserRole> notifier = ValueNotifier<UserRole>(UserRole.consumer);

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static Future<UserRole> getRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _hasExplicitValue = raw != null;
      final role = UserRoleX.fromId(raw);
      if (notifier.value != role) notifier.value = role;
      return role;
    }

    final value = await _secure.read(key: _key);
    _hasExplicitValue = value != null;
    final role = UserRoleX.fromId(value);
    if (notifier.value != role) notifier.value = role;
    return role;
  }

  static Future<void> setRole(UserRole role) async {
    _hasExplicitValue = true;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, role.id);
      if (notifier.value != role) notifier.value = role;
      return;
    }

    await _secure.write(key: _key, value: role.id);
    if (notifier.value != role) notifier.value = role;
  }

  static Future<void> clear() async {
    _hasExplicitValue = false;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      if (notifier.value != UserRole.consumer) notifier.value = UserRole.consumer;
      return;
    }

    await _secure.delete(key: _key);
    if (notifier.value != UserRole.consumer) notifier.value = UserRole.consumer;
  }
}
