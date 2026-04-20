import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../audio/audio.dart';
import '../../app/theme.dart';
import '../subscriptions/services/consumer_entitlement_gate.dart';
import '../videos/video.dart';
import '../videos/videos_repository.dart';
import 'reels/feed_screen.dart';
import 'pulse_energy_controller.dart';
import 'pulse_engagement_repository.dart';
import 'pulse_realtime_client.dart';

class PulseTab extends StatefulWidget {
  const PulseTab({
    super.key,
    required this.isActive,
    this.onBackToHome,
    this.initialVideoId,
  });

  /// True when this tab is currently selected/visible in the bottom navigation.
  /// Used to prevent background autoplay when inside an IndexedStack.
  final bool isActive;

  /// Callback to return to the consumer/home tab.
  final VoidCallback? onBackToHome;

  /// Optional: open the feed at a specific video.
  ///
  /// Used when launching Pulse from Home card taps.
  final String? initialVideoId;

  @override
  State<PulseTab> createState() => _PulseTabState();
}

class _PulseTabState extends State<PulseTab> with WidgetsBindingObserver {
  static const bool _useProductionReelsFeed = true;

  late Future<List<Video>> _videosFuture;

  final PulseEngagementRepository _engagementRepo = PulseEngagementRepository();
  StreamSubscription<User?>? _authSub;

  final PulseEnergyController _energy = PulseEnergyController();
  final PulseRealtimeClient _pulseRealtime = PulseRealtimeClient();

  final Set<String> _likedVideoIds = <String>{};
  final Set<String> _followedCreators = <String>{};

  final Set<String> _savedVideoIds = <String>{};
  final Set<String> _notInterestedVideoIds = <String>{};

  final Map<String, int> _commentCountOverrides = <String, int>{};
  final Map<String, List<PulseComment>> _commentsByVideoId =
      <String, List<PulseComment>>{};
  final Set<String> _loadingCommentsForVideoIds = <String>{};
  final TextEditingController _commentController = TextEditingController();

  Timer? _controlsTimer;
  Timer? _feedRefreshDebounce;
  bool _controlsVisible = true;

  bool _isCommentSheetOpen = false;
  String? _activeCommentsVideoId;
  bool _isSendingComment = false;

  bool _isDownloading = false;

  final PageController _pageController = PageController();
  int _index = 0;
  bool _didInitialJump = false;
  DateTime? _lastRealtimeRefreshAt;

  StreamSubscription<Map<String, dynamic>>? _pulseFeedUpdateSub;

  final Map<String, VideoPlayerController> _players = <String, VideoPlayerController>{};

  VideoPlayerController? get _player {
    if (_players.isEmpty) return null;
    return _players.values.first;
  }

  void _pauseBackgroundMusic() {
    final handler = maybeWeafricaAudioHandler;
    if (handler == null) return;
    // Pause any ongoing music playback so Pulse video audio doesn't overlap.
    unawaited(() async {
      try {
        await handler.pause();
      } catch (_) {}
    }());
  }

  void _pausePlayback() {
    for (final p in _players.values) {
      unawaited(() async {
        try {
          if (p.value.isInitialized) {
            await p.pause();
          }
        } catch (_) {}
      }());
    }
  }

  String? get _firebaseUid => FirebaseAuth.instance.currentUser?.uid;

  void _requireLogin() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Please sign in to interact.')),
    );
  }

  String _creatorKey(Video video) {
    final caption = (video.caption ?? '').trim();
    if (caption.isNotEmpty) return caption;
    final description = (video.description ?? '').trim();
    if (description.isNotEmpty) return description;
    return 'WeAfrica';
  }

  double _energyForVideo(Video video) {
    // Use real engagement counters if present; fall back to a calm baseline.
    final views = (video.viewsCount ?? 0).clamp(0, 1000000000);
    final likes = (video.likesCount ?? 0).clamp(0, 1000000000);
    final comments = (video.commentsCount ?? 0).clamp(0, 1000000000);

    double norm(int value, int cap) {
      if (value <= 0) return 0.0;
      if (value >= cap) return 1.0;
      return value / cap;
    }

    final v = norm(views, 50000);
    final l = norm(likes, 2000);
    final c = norm(comments, 200);

    final score = (v * 0.35) + (l * 0.45) + (c * 0.20);
    return (0.25 + 0.75 * score).clamp(0.25, 1.0);
  }

  void _setEnergyForVideo(Video video, {required bool isPlaying}) {
    final base = _energyForVideo(video);
    final next = isPlaying ? base : (base * 0.75);
    _energy.updateEnergy(next);
  }

  void _bumpEnergy(double amount) {
    final next = (_energy.energy + amount).clamp(0.0, 1.0);
    _energy.updateEnergy(next);
  }

  Future<void> _hydrateEngagementForUser(String uid) async {
    Set<String> liked = const <String>{};
    Set<String> followed = const <String>{};
    Set<String> saved = const <String>{};
    Set<String> notInterested = const <String>{};

    try {
      liked = await _engagementRepo.listLikedVideoIds(userId: uid);
    } catch (_) {}

    try {
      followed = await _engagementRepo.listFollowedArtistIds(userId: uid);
    } catch (_) {}

    try {
      saved = await _engagementRepo.listSavedVideoIds(userId: uid);
    } catch (_) {}

    try {
      notInterested =
          await _engagementRepo.listNotInterestedVideoIds(userId: uid);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _likedVideoIds
        ..clear()
        ..addAll(liked);
      _followedCreators
        ..clear()
        ..addAll(followed);
      _savedVideoIds
        ..clear()
        ..addAll(saved);
      _notInterestedVideoIds
        ..clear()
        ..addAll(notInterested);
    });
  }

  void _showControls() {
    if (_isCommentSheetOpen) return;
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _stopPlayback() {
    final players = _players.values.toList();
    _players.clear();
    for (final p in players) {
      unawaited(() async {
        try {
          if (p.value.isInitialized) {
            await p.pause();
          }
        } catch (_) {} finally {
          await p.dispose();
        }
      }());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videosFuture = VideosRepository().latest(limit: 24);
    unawaited(_initRealtimeFeedUpdates());

    if (widget.isActive) {
      _pauseBackgroundMusic();
    }

    // Keep engagement state in sync with auth changes.
    _authSub = FirebaseAuth.instance.userChanges().listen((user) {
      final uid = user?.uid;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _likedVideoIds.clear();
          _followedCreators.clear();
          _savedVideoIds.clear();
          _notInterestedVideoIds.clear();
          _commentCountOverrides.clear();
        });
        return;
      }
      unawaited(_hydrateEngagementForUser(uid));
    });

    final uid = _firebaseUid;
    if (uid != null) {
      unawaited(_hydrateEngagementForUser(uid));
    }

    _showControls();
  }

  Future<void> _initRealtimeFeedUpdates() async {
    _pulseFeedUpdateSub = _pulseRealtime.feedUpdates.listen((_) {
      _scheduleRealtimeRefresh();
    });

    try {
      await _pulseRealtime.connect();
    } catch (error, stackTrace) {
      developer.log(
        'Pulse realtime connect failed',
        name: 'WEAFRICA.Pulse',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _scheduleRealtimeRefresh() {
    _feedRefreshDebounce?.cancel();
    _feedRefreshDebounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final now = DateTime.now();
      final last = _lastRealtimeRefreshAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }

      _lastRealtimeRefreshAt = now;
      unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant PulseTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When leaving the tab, pause video playback so it doesn't continue in background.
    if (oldWidget.isActive && !widget.isActive) {
      _pausePlayback();
    }

    // When returning to the tab, resume if we have an initialized controller.
    if (!oldWidget.isActive && widget.isActive) {
      _pauseBackgroundMusic();
      final p = _player;
      if (p != null && p.value.isInitialized) {
        unawaited(p.play());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _authSub = null;
    _pulseFeedUpdateSub?.cancel();
    _pulseFeedUpdateSub = null;
    _controlsTimer?.cancel();
    _feedRefreshDebounce?.cancel();
    _pageController.dispose();
    _commentController.dispose();
    _energy.dispose();
    unawaited(_pulseRealtime.dispose());
    _stopPlayback();
    super.dispose();
  }

  Future<void> _startDownload(Video video) async {
    final allowed = await ConsumerEntitlementGate.instance.ensureAllowed(
      context,
      capability: ConsumerCapability.downloads,
    );
    if (!mounted) return;
    if (!allowed) {
      return;
    }

    final downloadUri = video.downloadUri ?? video.videoUri;
    if (downloadUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No download link available.')),
      );
      return;
    }

    if (video.allowDownload == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloads are disabled for this video.')),
      );
      return;
    }

    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(downloadUri);
      final response = await request.close();

      final dir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${dir.path}/pulse_downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final filename = '${video.id}.mp4';
      final file = File('${downloadsDir.path}/$filename');
      sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to app downloads.')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download failed.')));
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = _player;
    if (p == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.isActive && p.value.isInitialized) {
          unawaited(p.play());
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _pausePlayback();
        break;
      case AppLifecycleState.hidden:
        _pausePlayback();
        break;
      case AppLifecycleState.detached:
        _pausePlayback();
        break;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _videosFuture = VideosRepository().latest(limit: 24);
    });
    await _videosFuture;
  }

  Future<void> _ensurePlayerFor(Video video) async {
    final videoId = video.id;
    if (_players.containsKey(videoId)) return;

    final uri = video.videoUri;
    if (uri == null) return;

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      controller.setLooping(true);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _players[videoId] = controller;
      setState(() {});
    } catch (e) {
      await controller.dispose();
    }
  }

  Future<void> _loadCommentsForVideo(String videoId) async {
    if (_loadingCommentsForVideoIds.contains(videoId)) return;
    _loadingCommentsForVideoIds.add(videoId);
    if (mounted) setState(() {});

    try {
      final comments = await _engagementRepo.listComments(
        videoId: videoId,
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _commentsByVideoId[videoId] = comments;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not load comments.')),
        );
    } finally {
      _loadingCommentsForVideoIds.remove(videoId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleComments(Video video) async {
    final isOpen = _activeCommentsVideoId == video.id;
    if (isOpen) {
      setState(() {
        _activeCommentsVideoId = null;
        _isCommentSheetOpen = false;
        _commentController.clear();
      });
      _showControls();
      return;
    }

    setState(() {
      _activeCommentsVideoId = video.id;
      _isCommentSheetOpen = true;
      _commentController.clear();
    });
    await _loadCommentsForVideo(video.id);
  }

  Future<void> _sendInlineComment(Video video) async {
    final me = _firebaseUid;
    if (me == null) {
      _requireLogin();
      return;
    }
    final trimmed = _commentController.text.trim();
    if (trimmed.isEmpty || _isSendingComment) return;

    setState(() {
      _isSendingComment = true;
    });

    try {
      await _engagementRepo.addComment(
        videoId: video.id,
        userId: me,
        comment: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _commentController.clear();
        _commentCountOverrides[video.id] =
            (_commentCountOverrides[video.id] ?? 0) + 1;
      });
      await _loadCommentsForVideo(video.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not send comment.')),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingComment = false;
        });
      }
    }
  }

  Widget _buildInlineComments(Video video) {
    final uid = _firebaseUid;
    final isLoading = _loadingCommentsForVideoIds.contains(video.id);
    final comments = _commentsByVideoId[video.id] ?? const <PulseComment>[];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Comments',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close comments',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _activeCommentsVideoId = null;
                    _isCommentSheetOpen = false;
                    _commentController.clear();
                  });
                  _showControls();
                },
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          SizedBox(
            height: 140,
            child: isLoading && comments.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : comments.isEmpty
                    ? Center(
                        child: Text(
                          'Be the first to comment.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: comments.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 12,
                          color: AppColors.border,
                        ),
                        itemBuilder: (context, i) {
                          final c = comments[i];
                          final name = (c.displayName ?? c.username ?? '').trim();
                          final handle = name.isNotEmpty
                              ? name
                              : c.userId.trim().isEmpty
                                  ? 'User'
                                  : (c.userId.length <= 10
                                      ? c.userId
                                      : '${c.userId.substring(0, 6)}…');

                          return Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$handle  ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: c.comment),
                              ],
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  enabled: uid != null,
                  decoration: InputDecoration(
                    hintText:
                        uid == null ? 'Sign in to comment…' : 'Add a comment…',
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                      borderSide: BorderSide(color: AppColors.stageGold),
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendInlineComment(video),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Send comment',
                onPressed: (uid == null || _isSendingComment)
                    ? null
                    : () => _sendInlineComment(video),
                icon: Icon(
                  Icons.send_rounded,
                  color: (uid == null || _isSendingComment)
                      ? AppColors.textMuted
                      : AppColors.stageGold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shareVideo(Video video) async {
    final uri = video.videoUri;
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No video link available.')));
      return;
    }

    final shareText = 'Watch on WeAfrica Music • ${uri.toString()}';
    await Share.share(shareText);

    final uid = _firebaseUid;
    if (uid != null) {
      unawaited(
        _engagementRepo.recordShare(videoId: video.id, userId: uid),
      );
    }
  }

  Future<void> _openReportSheet(BuildContext context, Video video) async {
    final uid = _firebaseUid;
    if (uid == null) {
      _requireLogin();
      return;
    }

    const reasons = <({String value, String label})>[
      (value: 'copyright_infringement', label: 'Copyright infringement'),
      (value: 'nudity_sexual_content', label: 'Nudity or sexual content'),
      (value: 'hate_violence', label: 'Hate or violence'),
      (value: 'spam_scam', label: 'Spam or scam'),
      (value: 'harassment', label: 'Harassment'),
      (value: 'fake_account', label: 'Fake account'),
      (value: 'other', label: 'Other'),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text(
                'Report',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...reasons.map(
                (r) => ListTile(
                  leading: Icon(
                    Icons.flag_outlined,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  title: Text(
                    r.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(r.value),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    final reason = (selected ?? '').trim();
    if (reason.isEmpty) return;

    try {
      await _engagementRepo.reportVideo(
        videoId: video.id,
        reason: reason,
        reporterId: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(this.context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not submit report.')));
    }
  }

  Future<void> _openMoreActions(BuildContext context, Video video) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) {
        final uid = _firebaseUid;
        final isSaved = _savedVideoIds.contains(video.id);
        final uri = video.videoUri;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text(
                'More',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                title: Text(
                  isSaved ? 'Unsave' : 'Save',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (uid == null) {
                    _requireLogin();
                    return;
                  }
                  final next = !isSaved;
                  setState(() {
                    if (next) {
                      _savedVideoIds.add(video.id);
                    } else {
                      _savedVideoIds.remove(video.id);
                    }
                  });
                  unawaited(() async {
                    try {
                      await _engagementRepo.setSaved(
                        videoId: video.id,
                        userId: uid,
                        saved: next,
                      );
                    } catch (_) {
                      if (!mounted) return;
                      setState(() {
                        if (isSaved) {
                          _savedVideoIds.add(video.id);
                        } else {
                          _savedVideoIds.remove(video.id);
                        }
                      });
                      ScaffoldMessenger.of(this.context)
                        ..removeCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('Could not save right now.')),
                        );
                    }
                  }());
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.block_outlined,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                title: const Text(
                  'Not interested',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (uid == null) {
                    _requireLogin();
                    return;
                  }

                  setState(() {
                    _notInterestedVideoIds.add(video.id);
                  });

                  unawaited(() async {
                    try {
                      await _engagementRepo.setNotInterested(
                        videoId: video.id,
                        userId: uid,
                        notInterested: true,
                      );
                    } catch (_) {
                      if (!mounted) return;
                      setState(() {
                        _notInterestedVideoIds.remove(video.id);
                      });
                      ScaffoldMessenger.of(this.context)
                        ..removeCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Could not hide this video right now.'),
                          ),
                        );
                      return;
                    }

                    if (!mounted) return;
                    if (_pageController.hasClients) {
                      final next = _index;
                      unawaited(
                        _pageController.animateToPage(
                          next,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
                      );
                    }
                  }());
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.flag_outlined,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                title: const Text(
                  'Report',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_openReportSheet(this.context, video));
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.link,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                title: const Text(
                  'Copy link',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (uri == null) {
                    ScaffoldMessenger.of(this.context)
                      ..removeCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('No video link available.')),
                      );
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: uri.toString()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context)
                    ..removeCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Link copied.')));
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.download_outlined,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                title: const Text(
                  'Download',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_startDownload(video));
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  String _formatCount(int? value) {
    final v = value ?? 0;
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_useProductionReelsFeed) {
      return ReelFeedScreen(
        onAuthRequired: _requireLogin,
      );
    }

    return FutureBuilder<List<Video>>(
      future: _videosFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          developer.log(
            'Pulse videos failed to load',
            name: 'WEAFRICA.Pulse',
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
          );

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not load videos. Please try again.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          );
        }

        final allVideos = snapshot.data ?? const <Video>[];
        final videos = allVideos
            .where((v) => !_notInterestedVideoIds.contains(v.id))
            .toList(growable: false);
        if (videos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              allVideos.isEmpty
                  ? 'No videos yet.'
                  : 'No videos available right now.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          );
        }

        if (_index >= videos.length) {
          final clamped = videos.isEmpty ? 0 : (videos.length - 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(clamped);
            }
            setState(() {
              _index = clamped;
            });
          });
        }

        // If Pulse was launched from Home with a target video id,
        // jump to that page once (best-effort).
        final targetId = widget.initialVideoId;
        if (!_didInitialJump &&
            targetId != null &&
            targetId.trim().isNotEmpty) {
          final idx = videos.indexWhere((v) => v.id == targetId);
          if (idx >= 0) {
            _didInitialJump = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _pageController.jumpToPage(idx);
              setState(() {
                _index = idx;
              });
            });
          } else {
            _didInitialJump = true;
          }
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              _ensurePlayerFor(video);

              final player = _players[video.id];
              final hasVideo = player?.value.isInitialized ?? false;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Video section
                    VisibilityDetector(
                      key: Key('video-${video.id}'),
                      onVisibilityChanged: (info) {
                        final visibleFraction = info.visibleFraction;
                        final p = _players[video.id];
                        if (p == null || !p.value.isInitialized) return;
                        if (visibleFraction > 0.5) {
                          if (!p.value.isPlaying) {
                            p.play();
                            _setEnergyForVideo(video, isPlaying: true);
                          }
                        } else {
                          if (p.value.isPlaying) {
                            p.pause();
                            _setEnergyForVideo(video, isPlaying: false);
                          }
                        }
                      },
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: hasVideo && player != null
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: player.value.size.width,
                                  height: player.value.size.height,
                                  child: VideoPlayer(player),
                                ),
                              )
                            : Container(
                                color: AppColors.surface2,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                    ),

                    // Metadata and actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Creator info
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundImage: video.thumbnailUri != null
                                    ? NetworkImage(video.thumbnailUri.toString())
                                    : null,
                                child: video.thumbnailUri == null
                                    ? Text(
                                        _creatorKey(video).substring(0, 1).toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _creatorKey(video),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              // Follow button
                              Builder(
                                builder: (context) {
                                  final creatorName = _creatorKey(video).trim();
                                  final artistId = (video.artistId ?? '').trim();
                                  final creatorUid = (video.creatorUid ?? '').trim();
                                  final followId = artistId.isNotEmpty
                                      ? artistId
                                      : (creatorUid.isNotEmpty ? creatorUid : creatorName);

                                  final isFollowing = _followedCreators.contains(followId) ||
                                      (artistId.isNotEmpty && _followedCreators.contains(artistId)) ||
                                      (creatorUid.isNotEmpty && _followedCreators.contains(creatorUid)) ||
                                      _followedCreators.contains(creatorName);

                                  return TextButton(
                                    onPressed: () {
                                      final uid = _firebaseUid;
                                      if (uid == null) {
                                        _requireLogin();
                                        return;
                                      }

                                      if (isFollowing) return;
                                      const nextFollowing = true;

                                      setState(() {
                                        _followedCreators.add(followId);
                                      });
                                      HapticFeedback.selectionClick();
                                      _bumpEnergy(0.12);

                                      unawaited(() async {
                                        try {
                                          await _engagementRepo.setFollow(
                                            artistId: followId,
                                            userId: uid,
                                            following: nextFollowing,
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          setState(() {
                                            _followedCreators.remove(followId);
                                          });
                                          final messenger = ScaffoldMessenger.of(this.context);
                                          messenger.removeCurrentSnackBar();
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Could not follow right now.'),
                                            ),
                                          );
                                        }
                                      }());
                                    },
                                    child: Text(
                                      isFollowing ? 'Following' : 'Follow',
                                      style: TextStyle(
                                        color: isFollowing ? AppColors.textSecondary : AppColors.brandBlue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Caption
                          if (video.caption != null && video.caption!.isNotEmpty)
                            Text(
                              video.caption!,
                              style: const TextStyle(fontSize: 14),
                            ),

                          const SizedBox(height: 12),

                          // Engagement buttons
                          Row(
                            children: [
                              // Like
                              _LikeAction(
                                isLiked: _likedVideoIds.contains(video.id),
                                countLabel: _formatCount(
                                  (video.likesCount ?? 0) +
                                      (_likedVideoIds.contains(video.id) ? 1 : 0),
                                ),
                                onTap: () {
                                  final uid = _firebaseUid;
                                  if (uid == null) {
                                    _requireLogin();
                                    return;
                                  }

                                  final wasLiked = _likedVideoIds.contains(video.id);
                                  final nextLiked = !wasLiked;
                                  setState(() {
                                    if (nextLiked) {
                                      _likedVideoIds.add(video.id);
                                    } else {
                                      _likedVideoIds.remove(video.id);
                                    }
                                  });
                                  HapticFeedback.selectionClick();
                                  _bumpEnergy(nextLiked ? 0.18 : 0.08);

                                  unawaited(() async {
                                    try {
                                      await _engagementRepo.setLike(
                                        videoId: video.id,
                                        userId: uid,
                                        liked: nextLiked,
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setState(() {
                                        if (wasLiked) {
                                          _likedVideoIds.add(video.id);
                                        } else {
                                          _likedVideoIds.remove(video.id);
                                        }
                                      });
                                      final messenger = ScaffoldMessenger.of(this.context);
                                      messenger.removeCurrentSnackBar();
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Could not like right now.'),
                                        ),
                                      );
                                    }
                                  }());
                                },
                              ),

                              const SizedBox(width: 16),

                              // Comment
                              _CommentAction(
                                countLabel: _formatCount(
                                  (video.commentsCount ?? 0) +
                                      (_commentCountOverrides[video.id] ?? 0),
                                ),
                                onTap: () {
                                  _bumpEnergy(0.10);
                                  unawaited(_toggleComments(video));
                                },
                              ),

                              const SizedBox(width: 16),

                              // Share
                              _ShareAction(
                                onTap: () {
                                  _bumpEnergy(0.06);
                                  unawaited(_shareVideo(video));
                                },
                              ),

                              const Spacer(),

                              // More
                              _MoreAction(
                                onTap: () {
                                  _bumpEnergy(0.06);
                                  _openMoreActions(context, video);
                                },
                              ),
                            ],
                          ),

                          if (_activeCommentsVideoId == video.id)
                            _buildInlineComments(video),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _LikeAction extends StatelessWidget {
  const _LikeAction({
    required this.isLiked,
    required this.countLabel,
    required this.onTap,
  });

  final bool isLiked;
  final String countLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AnimatedScale(
            scale: isLiked ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked
                  ? AppColors.stageGold
                  : Colors.white.withValues(alpha: 0.82),
              size: 27,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            countLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.70),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({required this.countLabel, required this.onTap});

  final String countLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 26,
            color: Colors.white.withValues(alpha: 0.82),
          ),
          const SizedBox(height: 4),
          Text(
            countLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.70),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            Icons.share_outlined,
            size: 26,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ],
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            Icons.more_horiz,
            size: 26,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ],
      ),
    );
  }
}
