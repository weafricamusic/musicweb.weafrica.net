import 'package:flutter/material.dart';
import 'models/live_args.dart';

/// Main live screen that handles both viewing and hosting live streams.
class LiveScreen extends StatelessWidget {
  final LiveArgs args;

  const LiveScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.live_tv, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              args.isBattle ? 'Live Battle' : 'Live Stream',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Host: ${args.hostName}',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            const Text('Live streaming coming soon'),
          ],
        ),
      ),
    );
  }
}