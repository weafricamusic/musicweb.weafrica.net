import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../live_events/events_tab_screen.dart';

class LibraryEventsScreen extends StatelessWidget {
  const LibraryEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'EVENTS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
        ),
      ),
      body: const EventsTabScreen(showBattles: false),
    );
  }
}
