import 'package:flutter/material.dart';

import '../auth/user_role.dart';
import '../auth/user_role_resolver.dart';
import 'subscription_screen.dart';

class RoleBasedSubscriptionScreen extends StatelessWidget {
  const RoleBasedSubscriptionScreen({
    super.key,
    this.roleOverride,
    this.showComparisonTable = true,
  });

  final UserRole? roleOverride;
  final bool showComparisonTable;

  @override
  Widget build(BuildContext context) {
    final override = roleOverride;
    if (override != null) {
      return SubscriptionScreen(
        initialCatalog: _catalogFor(override),
        userRole: override,
        showCatalogToggle: false,
        showComparisonTable: showComparisonTable,
      );
    }

    return FutureBuilder<UserRole>(
      future: UserRoleResolver.resolveCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data ?? UserRole.consumer;
        return SubscriptionScreen(
          initialCatalog: _catalogFor(role),
          userRole: role,
          showCatalogToggle: false,
          showComparisonTable: showComparisonTable,
        );
      },
    );
  }

  SubscriptionCatalog _catalogFor(UserRole role) {
    if (role == UserRole.consumer) {
      return SubscriptionCatalog.listener;
    } else if (role == UserRole.artist || role == UserRole.dj) {
      return SubscriptionCatalog.creator;
    }
    return SubscriptionCatalog.listener;
  }
}
