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
        final ok = await LiveCoordinator.instance.startSoloLive(
          title: 'Test Live Stream',
          hostName: 'Test Artist',
        );
        
        if (ok && context.mounted) {
          // Navigate to SoloLiveStreamScreen
          // The screen should use LiveCoordinator.instance.rtcService.localVideoView()
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Live started!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start live')),
          );
        }
      },
    );
  }
}
