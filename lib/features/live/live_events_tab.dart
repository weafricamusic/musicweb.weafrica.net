import 'package:flutter/material.dart';

import 'screens/live_feed_screen.dart';

/// Home-tab compatibility wrapper for the events section.
class LiveEventsTab extends StatelessWidget {
  const LiveEventsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const LiveFeedScreen();
  }
}
