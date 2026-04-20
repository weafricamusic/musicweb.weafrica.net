import 'package:flutter/material.dart';

import 'pulse_layers.dart';

/// WEAFRICA MUSIC — PULSE FEED VIDEO ITEM
/// Each video has pulse, engagement buttons, audio info.
class PulseFeedItem extends StatelessWidget {
  const PulseFeedItem({
    super.key,
    required this.videoUrl,
    required this.songTitle,
    required this.artistName,
    required this.onLike,
    required this.onComment,
    required this.onFollow,
    this.onShare,
    this.onDownload,
    this.video,
    this.pulseColor,
    this.pulseSize = PulsePresets.sizeMvp,
  });

  final String videoUrl;
  final String songTitle;
  final String artistName;

  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onFollow;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;

  /// Real video widget (e.g., VideoPlayer). If null, shows a simple loading state.
  final Widget? video;

  final Color? pulseColor;
  final double pulseSize;

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    final fgMuted = Colors.white70;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: video ??
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
        ),

        // Pulse layers
        Center(
          child: PulseContainer(
            size: pulseSize,
            color: pulseColor ?? PulsePresets.accent,
          ),
        ),

        // Engagement buttons
        Positioned(
          right: 16,
          bottom: 100,
          child: Column(
            children: [
              IconButton(
                onPressed: onLike,
                icon: Icon(Icons.favorite, color: fg, size: 32),
              ),
              IconButton(
                onPressed: onComment,
                icon: Icon(Icons.comment, color: fg, size: 32),
              ),
              IconButton(
                onPressed: onFollow,
                icon: Icon(Icons.person_add, color: fg, size: 32),
              ),
              if (onShare != null)
                IconButton(
                  onPressed: onShare,
                  icon: Icon(Icons.share, color: fg, size: 32),
                ),
              if (onDownload != null)
                IconButton(
                  onPressed: onDownload,
                  icon: Icon(Icons.download, color: fg, size: 32),
                ),
            ],
          ),
        ),

        // Song info
        Positioned(
          left: 16,
          bottom: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                songTitle,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                artistName,
                style: TextStyle(color: fgMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
