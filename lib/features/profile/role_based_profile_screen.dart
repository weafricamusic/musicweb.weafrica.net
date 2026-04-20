import 'package:flutter/material.dart';

import '../artist_dashboard/screens/artist_profile_screen.dart';
import '../auth/user_role.dart';
import '../auth/user_role_intent_store.dart';
import '../auth/user_role_resolver.dart';
import '../dj_dashboard/screens/dj_profile_screen.dart';
import 'profile_screen.dart';

class RoleBasedProfileScreen extends StatelessWidget {
  const RoleBasedProfileScreen({super.key, this.roleOverride});

  final UserRole? roleOverride;

  @override
  Widget build(BuildContext context) {
    final override = roleOverride;
    if (override != null) {
      // Defensive: roleOverride is a UI hint (stored locally). Only show
      // creator profile screens when the backend role actually resolves to
      // a creator; otherwise consumers can end up seeing the artist profile.
      if (override == UserRole.consumer) {
        return _screenFor(override);
      }

      return FutureBuilder<UserRole>(
        future: UserRoleResolver.resolveCurrentUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final resolved = snapshot.data ?? UserRole.consumer;
          final isCreator = resolved == UserRole.artist || resolved == UserRole.dj;
          return _screenFor(isCreator ? resolved : UserRole.consumer);
        },
      );
    }

    return FutureBuilder<(UserRole intent, UserRole resolved)>(
      future: () async {
        final intent = await UserRoleIntentStore.getRole();
        final resolved = await UserRoleResolver.resolveCurrentUser();
        return (intent, resolved);
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        if (data == null) return _screenFor(UserRole.consumer);

        final intentRole = data.$1;
        final resolvedRole = data.$2;

        // Listener mode must stay on the consumer Profile screen even when
        // the backend role resolves to a creator.
        if (intentRole == UserRole.consumer) {
          return _screenFor(UserRole.consumer);
        }

        final isCreator = resolvedRole == UserRole.artist || resolvedRole == UserRole.dj;
        return _screenFor(isCreator ? resolvedRole : UserRole.consumer);
      },
    );
  }

  Widget _screenFor(UserRole role) {
    if (role == UserRole.artist) {
      return const ArtistProfileScreen();
    }

    if (role == UserRole.dj) {
      return const DjProfileScreen();
    }

    return ProfileScreen(roleOverride: role);
  }
}
