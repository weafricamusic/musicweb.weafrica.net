import 'package:flutter/material.dart';

import '../../artist_dashboard/screens/artist_earnings_screen.dart';
import '../../auth/user_role.dart';
import '../../auth/user_role_resolver.dart';
import '../../dj_dashboard/screens/dj_earnings_screen.dart';

class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserRole>(
      future: UserRoleResolver.resolveCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data ?? UserRole.consumer;
        return switch (role) {
          UserRole.artist => const ArtistEarningsScreen(),
          UserRole.dj => const DjEarningsScreen(),
          _ => Scaffold(
              appBar: AppBar(title: const Text('Earnings')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Earnings are available for artist and DJ accounts.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        };
      },
    );
  }
}
