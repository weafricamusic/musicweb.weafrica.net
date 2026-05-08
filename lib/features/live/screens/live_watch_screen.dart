import 'package:flutter/material.dart';

/// Screen for watching a live stream.
class LiveWatchScreen extends StatelessWidget {
  final String? channelId;
  final String? hostName;

  const LiveWatchScreen({super.key, this.channelId, this.hostName});

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
            const Text(
              'Live stream coming soon',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}