import 'package:flutter/material.dart';

/// Stub: Vertical battle feed screen - full-screen vertical battle viewing.
class VerticalBattleFeedScreen extends StatelessWidget {
  final String? initialChannelId;

  const VerticalBattleFeedScreen({super.key, this.initialChannelId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_mma, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Battle feed coming soon',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            if (initialChannelId != null && initialChannelId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Channel: $initialChannelId',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}