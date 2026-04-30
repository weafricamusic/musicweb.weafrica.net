import 'package:flutter/material.dart';

import 'services/live_coordinator.dart';

/// Quick test widget - Add this to your Artist Dashboard "Go Live" button
class GoLiveButton extends StatelessWidget {
  const GoLiveButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.videocam, color: Colors.white),
      label: const Text('GO LIVE', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      ),
      onPressed: () async {
        try {
          await LiveCoordinator.instance.startSoloLive(
            channelId: 'test_channel_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Test Live Stream',
            userId: 'test_user_id',
            userName: 'Test Artist',
          );
          
          if (context.mounted) {
            // Navigate to SoloLiveStreamScreen
            // The screen should use LiveCoordinator.instance.localVideoPreview
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Live started!')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to start live')),
            );
          }
        }
      },
    );
  }
}