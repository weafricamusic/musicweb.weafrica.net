import 'package:flutter/material.dart';

import 'screens/live_feed_screen.dart';

/// Home-tab compatibility wrapper.
///
/// The old home UI navigated to a swipe-based live experience.
/// The current app uses `LiveFeedScreen` as the Live/Events hub.
class LiveSwiperPage extends StatelessWidget {
  const LiveSwiperPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LiveFeedScreen();
  }
}
