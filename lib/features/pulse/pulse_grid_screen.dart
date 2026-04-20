import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../videos/video.dart';
import '../videos/videos_repository.dart';
import 'reels/feed_screen.dart';

class PulseGridScreen extends StatefulWidget {
  const PulseGridScreen({
    super.key,
    this.onBackToHome,
  });

  final VoidCallback? onBackToHome;

  @override
  State<PulseGridScreen> createState() => _PulseGridScreenState();
}

class _PulseGridScreenState extends State<PulseGridScreen> {
  late Future<List<Video>> _videosFuture;

  @override
  void initState() {
    super.initState();
    _videosFuture = VideosRepository().latest(limit: 60);
  }

  Future<void> _reload() async {
    setState(() {
      _videosFuture = VideosRepository().latest(limit: 60);
    });
    await _videosFuture;
  }

  void _openVideo() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) => const ReelFeedScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(slide),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PulseGridHeader(onBackToHome: widget.onBackToHome),
            Expanded(
              child: FutureBuilder<List<Video>>(
                future: _videosFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load trending videos.'),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }

                  final videos = snap.data ?? const <Video>[];
                  if (videos.isEmpty) {
                    return const Center(child: Text('No videos yet.'));
                  }

                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 120),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        childAspectRatio: 9 / 16,
                      ),
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        final video = videos[index];
                        return _PulseGridTile(
                          key: ValueKey(video.id),
                          video: video,
                          onTap: _openVideo,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseGridHeader extends StatelessWidget {
  const _PulseGridHeader({this.onBackToHome});

  final VoidCallback? onBackToHome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          if (onBackToHome != null)
            _HeaderIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back to Home',
              onTap: onBackToHome!,
            )
          else
            const SizedBox(width: 40),
          const Expanded(
            child: Text(
              'Trending',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ),
          _HeaderIconButton(
            icon: Icons.camera_alt_outlined,
            tooltip: 'Create',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
      ),
    );
  }
}

class _PulseGridTile extends StatelessWidget {
  const _PulseGridTile({
    super.key,
    required this.video,
    required this.onTap,
  });

  final Video video;
  final VoidCallback onTap;

  String _compactCount(int? value) {
    final n = value ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUri;

    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image.network(
              thumb.toString(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: Colors.black87,
                child: Center(child: Icon(Icons.play_circle_fill, size: 28)),
              ),
            )
          else
            const ColoredBox(
              color: Colors.black87,
              child: Center(child: Icon(Icons.play_circle_fill, size: 28)),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              height: 40,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(
                    _compactCount(video.viewsCount),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  const Spacer(),
                  const Icon(Icons.favorite, size: 12, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(
                    _compactCount(video.likesCount),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}