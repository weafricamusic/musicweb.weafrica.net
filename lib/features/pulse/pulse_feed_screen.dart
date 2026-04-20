import 'package:flutter/material.dart';

import 'pulse_feed_item.dart';

/// WEAFRICA MUSIC — PULSE FEED SCREEN
/// Vertical auto-scrolling feed with persistent state.
class PulseFeedScreen extends StatefulWidget {
  /// Expected shape:
  /// `[{"url": "...", "song": "...", "artist": "..."}]`
  const PulseFeedScreen({
    super.key,
    required this.videos,
    this.initialIndex = 0,
  });

  final List<Map<String, String>> videos;
  final int initialIndex;

  @override
  State<PulseFeedScreen> createState() => _PulseFeedScreenState();
}

class _PulseFeedScreenState extends State<PulseFeedScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        key: const PageStorageKey<String>('weafrica_pulse_feed'),
        scrollDirection: Axis.vertical,
        controller: _pageController,
        itemCount: widget.videos.length,
        itemBuilder: (context, index) {
          final video = widget.videos[index];

          final url = video['url'];
          final song = video['song'];
          final artist = video['artist'];

          if (url == null || song == null || artist == null) {
            return const Center(
              child: Text('Invalid video item'),
            );
          }

          return PulseFeedItem(
            videoUrl: url,
            songTitle: song,
            artistName: artist,
            onLike: () {},
            onComment: () {},
            onFollow: () {},
            onShare: () {},
            onDownload: () {},
          );
        },
      ),
    );
  }
}
