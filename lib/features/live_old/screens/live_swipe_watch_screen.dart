import 'package:flutter/material.dart';

/// Stub: Live swipe watch screen - TikTok-style vertical live stream browsing.
class LiveSwipeWatchScreen extends StatelessWidget {
  const LiveSwipeWatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.live_tv, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Live streams coming soon',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}