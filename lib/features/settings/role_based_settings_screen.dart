import 'package:flutter/material.dart';

import '../auth/user_role.dart';
import '../auth/user_role_intent_store.dart';
import '../auth/user_role_resolver.dart';
import 'creator_settings_screen.dart';
import 'settings_screen.dart';

class RoleBasedSettingsScreen extends StatelessWidget {
  const RoleBasedSettingsScreen({super.key, this.roleOverride});

  final UserRole? roleOverride;

  bool _isCreator(UserRole role) => role == UserRole.artist || role == UserRole.dj;

  @override
  Widget build(BuildContext context) {
    final override = roleOverride;
    if (override != null) {
      return _isCreator(override) ? const CreatorSettingsScreen() : const SettingsScreen();
    }

    return FutureBuilder<(UserRole resolved, UserRole intent)>(
      future: () async {
        final resolved = await UserRoleResolver.resolveCurrentUser();
        final intent = await UserRoleIntentStore.getRole();
        return (resolved, intent);
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return const SettingsScreen();
        }

        final resolvedRole = data.$1;
        final intentRole = data.$2;

        // Listener mode must stay in consumer settings even when the account
        // itelf is creator-enabled.
        if (intentRole == UserRole.consumer) {
          return const SettingsScreen();
        }

        return _isCreator(resolvedRole) ? const CreatorSettingsScreen() : const SettingsScreen();
      },
    );
  }
}
