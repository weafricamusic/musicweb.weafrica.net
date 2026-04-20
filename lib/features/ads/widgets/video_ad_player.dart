import 'package:flutter/material.dart';

import 'ad_player.dart';

/// Backwards-compatible wrapper requested by tooling/docs.
///
/// The app already uses [AdPlayer] for interstitials (including video via
/// `video_url`). This wrapper keeps the API stable while centralizing video-ad
/// playback under a clearly named widget.
class VideoAdPlayer extends StatelessWidget {
  const VideoAdPlayer({
    super.key,
    required this.ad,
    required this.onComplete,
    required this.onSkip,
    this.durationSeconds = 5,
  });

  final Map<String, dynamic> ad;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    return AdPlayer(
      ad: ad,
      onComplete: onComplete,
      onSkip: onSkip,
      durationSeconds: durationSeconds,
    );
  }
}
