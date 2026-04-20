import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_actions.dart';
import '../live/screens/live_feed_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WeAfrica Music'),
        actions: [
          TextButton(
            onPressed: () => AuthActions.signOut(),
            child: const Text('Sign out'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Signed in as ${user.email ?? user.uid}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            
            // Watch Live Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveFeedScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.live_tv),
              label: const Text('Watch Live Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
