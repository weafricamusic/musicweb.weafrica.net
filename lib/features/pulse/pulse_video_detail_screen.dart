import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../videos/video.dart';
import 'pulse_engagement_repository.dart';

class PulseVideoDetailScreen extends StatefulWidget {
  const PulseVideoDetailScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
  });

  final List<Video> videos;
  final int initialIndex;

  @override
  State<PulseVideoDetailScreen> createState() => _PulseVideoDetailScreenState();
}

class _PulseVideoDetailScreenState extends State<PulseVideoDetailScreen>
    with WidgetsBindingObserver {
  final PulseEngagementRepository _repo = PulseEngagementRepository();
  final Map<String, VideoPlayerController> _players = {};
  final PageController _pageController = PageController();

  final Set<String> _likedVideoIds = {};
  final Set<String> _savedVideoIds = {};
  final Set<String> _followedCreators = {};
  final Map<String, int> _likeCountOverrides = {};
  final Map<String, int> _commentCountOverrides = {};

  int _index = 0;
  int _playEpoch = 0;
  bool _videoMuted = true;
  bool _busyLike = false;
  bool _showUI = true;
  bool _showLikeBurst = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Video get _currentVideo =>
      widget.videos[_index.clamp(0, widget.videos.length - 1)];

  String _creatorId(Video video) {
    final uid = (video.creatorUid ?? '').trim();
    if (uid.isNotEmpty) return uid;
    final artist = (video.artistId ?? '').trim();
    if (artist.isNotEmpty) return artist;
    return '';
  }

  String _creatorHandle(Video video) {
    final uid = (video.creatorUid ?? '').trim();
    if (uid.isNotEmpty) return '@$uid';
    final artist = (video.artistId ?? '').trim();
    if (artist.isNotEmpty) return '@$artist';
    final caption = (video.caption ?? '').trim();
    if (caption.isNotEmpty) return '@$caption';
    return '@weafrica';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);

    final uid = _uid;
    if (uid != null) {
      unawaited(_hydrateEngagement(uid));
    }

    unawaited(_ensureWindowAndPlay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();

    for (final c in _players.values) {
      unawaited(c.dispose());
    }
    _players.clear();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_ensureWindowAndPlay());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        for (final c in _players.values) {
          unawaited(c.pause());
        }
        break;
    }
  }

  Future<void> _hydrateEngagement(String uid) async {
    try {
      final liked = await _repo.listLikedVideoIds(userId: uid);
      final saved = await _repo.listSavedVideoIds(userId: uid);
      final followed = await _repo.listFollowedArtistIds(userId: uid);

      if (!mounted) return;

      setState(() {
        _likedVideoIds
          ..clear()
          ..addAll(liked);
        _savedVideoIds
          ..clear()
          ..addAll(saved);
        _followedCreators
          ..clear()
          ..addAll(followed);
      });
    } catch (_) {}
  }

  Future<void> _ensureController(Video video) async {
    if (_players.containsKey(video.id)) return;
    final uri = video.videoUri;
    if (uri == null) return;

    final c = VideoPlayerController.networkUrl(uri);
    _players[video.id] = c;

    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(_videoMuted ? 0 : 1);

      if (_currentVideo.id == video.id) {
        await c.play();
      }

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      _players.remove(video.id);
      unawaited(c.dispose());
    }
  }

  void _cleanupControllers() {
    final keep = <String>{};

    if (_index >= 0) keep.add(widget.videos[_index].id);
    if (_index + 1 < widget.videos.length) {
      keep.add(widget.videos[_index + 1].id);
    }
    if (_index - 1 >= 0) {
      keep.add(widget.videos[_index - 1].id);
    }

    final remove =
        _players.keys.where((id) => !keep.contains(id)).toList();

    for (final id in remove) {
      final controller = _players[id];
      if (controller != null) {
        unawaited(controller.dispose());
      }
      _players.remove(id);
    }
  }

  Future<void> _ensureWindowAndPlay() async {
    final epoch = ++_playEpoch;
    final current = _currentVideo;

    await _ensureController(current);
    if (epoch != _playEpoch) return;

    for (final c in _players.values) {
      await c.pause();
    }

    final p = _players[current.id];
    if (p != null && p.value.isInitialized) {
      await p.play();
      await p.setVolume(_videoMuted ? 0.0 : 1.0);
    }

    _cleanupControllers();

    // View tracking is currently handled by feed-level services.
  }

  void _onPageScroll() {}

  Future<void> _onPageChanged(int page) async {
    if (!mounted || page == _index) return;
    setState(() {
      _index = page;
    });
    await _ensureWindowAndPlay();
  }

  Future<void> _toggleLike(Video video) async {
    if (_busyLike) return;
    final uid = _uid;
    if (uid == null) return;

    final next = !_likedVideoIds.contains(video.id);

    final previousLikeCount = _likeCountOverrides[video.id] ?? (video.likesCount ?? 0);

    setState(() {
      _busyLike = true;

      if (next) {
        _likedVideoIds.add(video.id);
        _likeCountOverrides[video.id] = previousLikeCount + 1;
      } else {
        _likedVideoIds.remove(video.id);
        _likeCountOverrides[video.id] = (previousLikeCount - 1).clamp(0, 1 << 30);
      }
    });

    try {
      await _repo.setLike(
        videoId: video.id,
        userId: uid,
        liked: next,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (next) {
          _likedVideoIds.remove(video.id);
        } else {
          _likedVideoIds.add(video.id);
        }
        _likeCountOverrides[video.id] = previousLikeCount;
      });
    }

    if (!mounted) return;
    setState(() => _busyLike = false);
  }

  Future<void> _toggleFollow(Video video) async {
    final uid = _uid;
    if (uid == null) return;

    final creator = _creatorId(video);
    if (creator.trim().isEmpty) return;
    final next = !_followedCreators.contains(creator);

    setState(() {
      if (next) {
        _followedCreators.add(creator);
      } else {
        _followedCreators.remove(creator);
      }
    });

    try {
      await _repo.setFollow(
        artistId: creator,
        userId: uid,
        following: next,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (next) {
          _followedCreators.remove(creator);
        } else {
          _followedCreators.add(creator);
        }
      });
    }
  }

  Future<void> _toggleSave(Video video) async {
    final uid = _uid;
    if (uid == null) return;

    final isSaved = _savedVideoIds.contains(video.id);
    final next = !isSaved;
    setState(() {
      if (next) {
        _savedVideoIds.add(video.id);
      } else {
        _savedVideoIds.remove(video.id);
      }
    });

    try {
      await _repo.setSaved(videoId: video.id, userId: uid, saved: next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isSaved) {
          _savedVideoIds.add(video.id);
        } else {
          _savedVideoIds.remove(video.id);
        }
      });
    }
  }

  Future<void> _openCommentSheet(Video video) async {
    final uid = _uid;
    if (uid == null) return;

    final controller = TextEditingController();

    final comment = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: TextField(
          controller: controller,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
    );

    try {
      if (comment == null || comment.trim().isEmpty) return;

      await _repo.addComment(
        videoId: video.id,
        userId: uid,
        comment: comment,
      );

      if (!mounted) return;
      setState(() {
        _commentCountOverrides[video.id] =
            (_commentCountOverrides[video.id] ??
                    video.commentsCount ??
                    0) +
                1;
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _share(Video video) async {
    if (video.videoUri == null) return;
    await Share.share(video.videoUri.toString());
    final uid = _uid;
    if (uid != null) {
      unawaited(_repo.recordShare(videoId: video.id, userId: uid));
    }
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_videoMuted;
    setState(() => _videoMuted = nextMuted);

    for (final c in _players.values) {
      if (c.value.isInitialized) {
        await c.setVolume(nextMuted ? 0.0 : 1.0);
      }
    }

    final active = _players[_currentVideo.id];
    if (!nextMuted && active != null && active.value.isInitialized && !active.value.isPlaying) {
      await active.play();
      await active.setVolume(1.0);
    }
  }

  void _showLikeBurstOnce() {
    if (!mounted) return;
    setState(() => _showLikeBurst = true);
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _showLikeBurst = false);
    });
  }

  Widget _video(Video video) {
    final c = _players[video.id];

    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () => setState(() => _showUI = !_showUI),
      onDoubleTap: () {
        _showLikeBurstOnce();
        unawaited(_toggleLike(video));
      },
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  String _compact(int? n) {
    final v = n ?? 0;
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  int _likeCountFor(Video video) {
    return _likeCountOverrides[video.id] ?? (video.likesCount ?? 0);
  }

  int _commentCountFor(Video video) {
    return _commentCountOverrides[video.id] ?? (video.commentsCount ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.videos.length,
        onPageChanged: (value) => unawaited(_onPageChanged(value)),
        itemBuilder: (context, i) {
          final v = widget.videos[i];
          final liked = _likedVideoIds.contains(v.id);
          final creatorId = _creatorId(v);
          final followed = creatorId.isNotEmpty && _followedCreators.contains(creatorId);
          final saved = _savedVideoIds.contains(v.id);
          final creatorHandle = _creatorHandle(v);

          return Stack(
            fit: StackFit.expand,
            children: [
              _video(v),

              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),

              if (_showUI) ...[
                Positioned(
                  top: 50,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _videoMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _toggleMute,
                    ),
                  ),
                ),

                Positioned(
                  right: 8,
                  bottom: 90,
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          const CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0xFF2A2A2A),
                            child: Icon(Icons.person, color: Colors.white70),
                          ),
                          if (!followed && creatorId.isNotEmpty)
                            const CircleAvatar(
                              radius: 8,
                              child: Icon(Icons.add, size: 12),
                            )
                        ],
                      ),

                      const SizedBox(height: 12),

                      _ActionIcon(
                        icon: liked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: _compact(_likeCountFor(v)),
                        color:
                            liked ? Colors.red : Colors.white,
                        onTap: () => _toggleLike(v),
                      ),

                      _ActionIcon(
                        icon: Icons.comment,
                        label: _compact(_commentCountFor(v)),
                        onTap: () => _openCommentSheet(v),
                      ),

                      _ActionIcon(
                        icon: Icons.send,
                        label: '',
                        onTap: () => _share(v),
                      ),

                      _ActionIcon(
                        icon: saved ? Icons.bookmark : Icons.bookmark_border,
                        label: '',
                        onTap: () => _toggleSave(v),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  left: 14,
                  right: 80,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            creatorHandle,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: creatorId.isEmpty ? null : () => _toggleFollow(v),
                            child: Text(
                                followed ? 'Following' : 'Follow'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        v.description ?? '',
                        style:
                            const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.music_note,
                              size: 14,
                              color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              v.title,
                              style: const TextStyle(
                                  color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (_showLikeBurst)
                const Center(
                  child: Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 110,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            if (label.isNotEmpty)
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}