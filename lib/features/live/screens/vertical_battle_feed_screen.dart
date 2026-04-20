import 'package:flutter/material.dart';

import 'live_battle_swipe_screen.dart';

/// Dedicated entry point for TikTok-style vertical battle feed browsing.
///
/// This wrapper keeps battle rendering logic centralized in
/// [LiveBattleSwipeScreen], which already uses a vertical PageView.
class VerticalBattleFeedScreen extends StatelessWidget {
  const VerticalBattleFeedScreen({
    super.key,
    this.initialChannelId,
  });

  final String? initialChannelId;

  @override
  Widget build(BuildContext context) {
    return LiveBattleSwipeScreen(initialChannelId: initialChannelId);
  }
}