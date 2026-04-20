import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_role.dart';

class UserRoleStore {
  static const String _key = 'weafrica_user_role';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static Future<UserRole> getRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return UserRoleX.fromId(prefs.getString(_key));
    }

    final value = await _secure.read(key: _key);
    return UserRoleX.fromId(value);
  }

  static Future<void> setRole(UserRole role) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, role.id);
      return;
    }

    await _secure.write(key: _key, value: role.id);
  }

  static Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      return;
    }

    await _secure.delete(key: _key);
  }
}
