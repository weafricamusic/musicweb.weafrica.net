import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../audio/audio.dart';
import '../../auth/user_role.dart';
import '../../social/screens/photo_song_post_mockup_screen.dart';
import '../../tracks/track.dart';
import '../../tracks/tracks_repository.dart';
import '../pulse_engagement_repository.dart';
import 'pagination_service.dart';
import 'reel_like_manager.dart';
import 'reel_video_player.dart';

class _PhotoPostComment {
  const _PhotoPostComment({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;
}

class ReelFeedScreen extends StatefulWidget {
  const ReelFeedScreen({
    super.key,
    this.pageSize = ReelPaginationService.defaultPageSize,
    this.onAuthRequired,
    this.onOpenArtistProfile,
  });

  final int pageSize;
  final VoidCallback? onAuthRequired;
  final void Function(String artistUserId)? onOpenArtistProfile;

  @override
  State<ReelFeedScreen> createState() => _ReelFeedScreenState();
}

class _ReelFeedScreenState extends State<ReelFeedScreen> {
  static const String _kReelsMutedPrefKey = 'reels.feed.muted';

  final PageController _pageController = PageController();
  final ReelPaginationService _pagination = ReelPaginationService();
  final ReelLikeManager _likeManager = ReelLikeManager();
  final PulseEngagementRepository _engagementRepo = PulseEngagementRepository();
  final TracksRepository _tracksRepository = TracksRepository();
  final Map<String, RealtimeChannel> _channelsByReelId = <String, RealtimeChannel>{};
  final Map<String, RealtimeChannel> _channelsByPhotoPostId = <String, RealtimeChannel>{};

  final Map<String, Track?> _trackCacheById = <String, Track?>{};
  final Map<String, Future<Track?>> _trackFetchById = <String, Future<Track?>>{};
  Timer? _photoSongStopTimer;
  String? _activePhotoPostId;

  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  List<ReelFeedEntry> _items = <ReelFeedEntry>[];
  ReelCursor? _nextCursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;

  int _activeIndex = 0;
  bool _muted = true;
  bool _showOverlayControls = true;
  final Set<String> _savedIds = <String>{};
  final Set<String> _favoriteIds = <String>{};
  final Set<String> _followedCreatorIds = <String>{};
  final Set<String> _likedPhotoPostIds = <String>{};

  String? get _firebaseUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _likeManager.addListener(_onLikeStateChanged);
    unawaited(_loadMutePreference());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _stopPhotoSongPlayback();
    _pageController.dispose();
    _likeManager.removeListener(_onLikeStateChanged);
    _likeManager.dispose();
    for (final channel in _channelsByReelId.values) {
      Supabase.instance.client.removeChannel(channel);
    }
    _channelsByReelId.clear();
    for (final channel in _channelsByPhotoPostId.values) {
      Supabase.instance.client.removeChannel(channel);
    }
    _channelsByPhotoPostId.clear();
    super.dispose();
  }

  void _stopPhotoSongPlayback() {
    _photoSongStopTimer?.cancel();
    _photoSongStopTimer = null;
    _activePhotoPostId = null;

    final handler = maybeWeafricaAudioHandler;
    if (handler == null) return;
    try {
      unawaited(handler.pause());
    } catch (_) {
      // ignore
    }
  }

  Future<Track?> _getTrackByIdCached(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return Future<Track?>.value(null);

    if (_trackCacheById.containsKey(trimmed)) {
      return Future<Track?>.value(_trackCacheById[trimmed]);
    }

    final inFlight = _trackFetchById[trimmed];
    if (inFlight != null) return inFlight;

    final future = _tracksRepository.getById(trimmed).then((track) {
      _trackCacheById[trimmed] = track;
      _trackFetchById.remove(trimmed);
      return track;
    }).catchError((_) {
      _trackCacheById[trimmed] = null;
      _trackFetchById.remove(trimmed);
      return null;
    });

    _trackFetchById[trimmed] = future;
    return future;
  }

  Future<void> _startPhotoSongPlayback(ReelFeedEntry entry) async {
    if (_muted) {
      _stopPhotoSongPlayback();
      return;
    }

    final postId = entry.itemId.trim();
    if (postId.isEmpty) return;
    if (_activePhotoPostId == postId) return;

    _photoSongStopTimer?.cancel();
    _photoSongStopTimer = null;
    _activePhotoPostId = postId;

    final songId = (entry.songId ?? '').trim();
    if (songId.isEmpty) return;

    // Ensure audio stack is ready (safe even if already initialized).
    if (!isWeAfricaAudioInitialized) {
      try {
        await initWeAfricaAudio();
      } catch (_) {
        return;
      }
    }

    final handler = maybeWeafricaAudioHandler;
    if (handler == null) return;

    final track = await _getTrackByIdCached(songId);
    if (!mounted) return;
    if (_activePhotoPostId != postId) return; // user scrolled away

    final uri = track?.audioUri;
    if (uri == null) return;

    try {
      await handler.playSingle(
        item: MediaItem(
          id: uri.toString(),
          title: track?.title ?? (entry.musicTitle ?? 'Photo + Song'),
          artist: track?.artist ?? (entry.musicArtist ?? 'Unknown Artist'),
          artUri: track?.artworkUri,
          duration: track?.duration,
        ),
        uri: uri,
      );

      final startSeconds = (entry.songStartSeconds ?? 0).clamp(0, 60 * 60);
      await handler.seek(Duration(seconds: startSeconds));
    } catch (_) {
      return;
    }

    final durationSeconds = (entry.songDurationSeconds ?? 15).clamp(1, 60);
    _photoSongStopTimer = Timer(Duration(seconds: durationSeconds), () {
      if (!mounted) return;
      if (_activePhotoPostId != postId) return;
      _stopPhotoSongPlayback();
    });
  }

  void _handleActiveItemChanged() {
    if (_items.isEmpty) return;
    if (_activeIndex < 0 || _activeIndex >= _items.length) return;
    final item = _items[_activeIndex];
    if (item.mediaType == 'photo_song') {
      unawaited(_startPhotoSongPlayback(item));
      return;
    }
    _stopPhotoSongPlayback();
  }

  void _onLikeStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMutePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_kReelsMutedPrefKey);
      if (stored == null || !mounted) return;
      setState(() {
        _muted = stored;
      });
    } catch (_) {
      // Keep default if persistence is unavailable.
    }
  }

  Future<void> _setMuted(bool value) async {
    setState(() {
      _muted = value;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kReelsMutedPrefKey, value);
    } catch (_) {
      // Non-fatal; UI state already updated.
    }
  }

  bool _ensureSignedIn() {
    if (_firebaseUid != null) return true;
    widget.onAuthRequired?.call();
    _showSnack('Please sign in to continue.');
    return false;
  }

  Future<void> _hydrateEngagementState() async {
    final uid = _firebaseUid;
    if (uid == null) return;

    try {
      final saved = await _engagementRepo.listSavedVideoIds(userId: uid);
      if (!mounted) return;
      setState(() {
        _savedIds
          ..clear()
          ..addAll(saved);
      });
    } catch (_) {}

    try {
      final followed = await _engagementRepo.listFollowedArtistIds(userId: uid);
      if (!mounted) return;
      setState(() {
        _followedCreatorIds
          ..clear()
          ..addAll(followed);
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _activeIndex = 0;
    });

    try {
      final page = await _pagination.fetchPage(limit: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
      unawaited(_hydrateEngagementState());
      unawaited(_hydratePhotoPostLikeState());
      _syncScopedRealtime();
      _handleActiveItemChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load reels. Pull to refresh.';
      });
    }
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    if (_items.isEmpty) return;

    final thresholdIndex = math.max(0, (_items.length * 0.7).floor() - 1);
    if (_activeIndex < thresholdIndex) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final page = await _pagination.fetchPage(
        cursor: _nextCursor,
        limit: widget.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = <ReelFeedEntry>[..._items, ...page.items];
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
      unawaited(_hydratePhotoPostLikeState());
      _syncScopedRealtime();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
      _showSnack('Failed to load more reels.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateEntry(String reelId, ReelFeedEntry Function(ReelFeedEntry current) update) {
    final index = _items.indexWhere((entry) => entry.id == reelId);
    if (index < 0) return;
    setState(() {
      final current = _items[index];
      final next = update(current);
      final mutable = List<ReelFeedEntry>.from(_items);
      mutable[index] = next;
      _items = mutable;
    });
  }

  ReelFeedEntry? _entryById(String reelId) {
    final index = _items.indexWhere((entry) => entry.id == reelId);
    if (index < 0) return null;
    return _items[index];
  }

  Set<String> _targetVisibleReelIds() {
    if (_items.isEmpty) return const <String>{};
    final ids = <String>{};
    final from = math.max(0, _activeIndex - 1);
    final to = math.min(_items.length - 1, _activeIndex + 1);
    for (var i = from; i <= to; i++) {
      if (_items[i].mediaType == 'video') {
        ids.add(_items[i].id);
      }
    }
    return ids;
  }

  Set<String> _targetVisiblePhotoPostIds() {
    if (_items.isEmpty) return const <String>{};
    final ids = <String>{};
    final from = math.max(0, _activeIndex - 1);
    final to = math.min(_items.length - 1, _activeIndex + 1);
    for (var i = from; i <= to; i++) {
      final entry = _items[i];
      if (entry.mediaType == 'photo_song') {
        final postId = entry.itemId.trim();
        if (postId.isNotEmpty) {
          ids.add(postId);
        }
      }
    }
    return ids;
  }

  void _updatePhotoPostEntryByPostId(String postId, ReelFeedEntry Function(ReelFeedEntry current) update) {
    final index = _items.indexWhere(
      (entry) => entry.mediaType == 'photo_song' && entry.itemId == postId,
    );
    if (index < 0) return;
    setState(() {
      final current = _items[index];
      final next = update(current);
      final mutable = List<ReelFeedEntry>.from(_items);
      mutable[index] = next;
      _items = mutable;
    });
  }

  void _syncScopedRealtime() {
    final targetIds = _targetVisibleReelIds();
    final existingIds = _channelsByReelId.keys.toSet();

    final toRemove = existingIds.difference(targetIds);
    for (final reelId in toRemove) {
      final channel = _channelsByReelId.remove(reelId);
      if (channel != null) {
        Supabase.instance.client.removeChannel(channel);
      }
    }

    final toAdd = targetIds.difference(existingIds);
    for (final reelId in toAdd) {
      final channel = Supabase.instance.client
          .channel('reel_scope_$reelId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'reels',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: reelId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              final likesCount = _toInt(row['likes_count']);
              final commentsCount = _toInt(row['comments_count']);
              final viewsCount = _toInt(row['views_count']);
              _updateEntry(
                reelId,
                (current) => current.copyWith(
                  likesCount: likesCount,
                  commentsCount: commentsCount,
                  viewsCount: viewsCount,
                ),
              );
              _likeManager.applyServerCount(reelId: reelId, likesCount: likesCount);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reel_likes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reel_id',
              value: reelId,
            ),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                final current = _entryById(reelId);
                if (current == null) return;
                final nextLikes = current.likesCount + 1;
                _updateEntry(
                  reelId,
                  (item) => item.copyWith(likesCount: nextLikes),
                );
                _likeManager.applyServerCount(
                  reelId: reelId,
                  likesCount: nextLikes,
                );
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                final current = _entryById(reelId);
                if (current == null) return;
                final nextLikes = math.max(0, current.likesCount - 1);
                _updateEntry(
                  reelId,
                  (item) => item.copyWith(likesCount: nextLikes),
                );
                _likeManager.applyServerCount(reelId: reelId, likesCount: nextLikes);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reel_comments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reel_id',
              value: reelId,
            ),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                _updateEntry(
                  reelId,
                  (current) => current.copyWith(commentsCount: current.commentsCount + 1),
                );
              }
            },
          )
          .subscribe();

      _channelsByReelId[reelId] = channel;
    }

    final targetPhotoPostIds = _targetVisiblePhotoPostIds();
    final existingPhotoPostIds = _channelsByPhotoPostId.keys.toSet();

    final toRemovePhoto = existingPhotoPostIds.difference(targetPhotoPostIds);
    for (final postId in toRemovePhoto) {
      final channel = _channelsByPhotoPostId.remove(postId);
      if (channel != null) {
        Supabase.instance.client.removeChannel(channel);
      }
    }

    final toAddPhoto = targetPhotoPostIds.difference(existingPhotoPostIds);
    for (final postId in toAddPhoto) {
      final channel = Supabase.instance.client
          .channel('photo_post_scope_$postId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'photo_song_post_likes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'post_id',
              value: postId,
            ),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                _updatePhotoPostEntryByPostId(
                  postId,
                  (current) => current.copyWith(likesCount: current.likesCount + 1),
                );

                final userId = (payload.newRecord['user_id'] ?? '').toString().trim();
                if (userId.isNotEmpty && userId == _firebaseUid) {
                  setState(() {
                    _likedPhotoPostIds.add(postId);
                  });
                }
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                _updatePhotoPostEntryByPostId(
                  postId,
                  (current) => current.copyWith(likesCount: math.max(0, current.likesCount - 1)),
                );

                final userId = (payload.oldRecord['user_id'] ?? '').toString().trim();
                if (userId.isNotEmpty && userId == _firebaseUid) {
                  setState(() {
                    _likedPhotoPostIds.remove(postId);
                  });
                }
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'photo_song_post_comments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'post_id',
              value: postId,
            ),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                _updatePhotoPostEntryByPostId(
                  postId,
                  (current) => current.copyWith(commentsCount: current.commentsCount + 1),
                );
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                _updatePhotoPostEntryByPostId(
                  postId,
                  (current) => current.copyWith(commentsCount: math.max(0, current.commentsCount - 1)),
                );
              }
            },
          )
          .subscribe();

      _channelsByPhotoPostId[postId] = channel;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _compactCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final k = value / 1000;
      final text = k >= 100 || k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${text}K';
    }
    final m = value / 1000000;
    final text = m >= 100 || m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
    return '${text}M';
  }

  Future<void> _hydratePhotoPostLikeState() async {
    final uid = _firebaseUid;
    if (uid == null) return;

    final postIds = _items
        .where((item) => item.mediaType == 'photo_song')
        .map((item) => item.itemId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (postIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _likedPhotoPostIds.clear();
      });
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('photo_song_post_likes')
          .select('post_id')
          .eq('user_id', uid)
          .inFilter('post_id', postIds);

      final liked = rows
          .whereType<Map>()
          .map((row) => (row['post_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      if (!mounted) return;
      setState(() {
        _likedPhotoPostIds
          ..clear()
          ..addAll(liked);
      });
    } catch (_) {
      // Best effort only.
    }
  }

  Future<List<_PhotoPostComment>> _listPhotoPostComments(String postId) async {
    final rows = await Supabase.instance.client
        .from('photo_song_post_comments')
        .select('id,user_id,content,created_at')
        .eq('post_id', postId)
        .order('created_at', ascending: true)
        .limit(100);

    return rows.whereType<Map>().map((row) {
      final id = (row['id'] ?? '').toString().trim();
      final userId = (row['user_id'] ?? '').toString().trim();
      final content = (row['content'] ?? '').toString().trim();
      final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString()) ?? DateTime.now().toUtc();
      return _PhotoPostComment(
        id: id,
        userId: userId,
        content: content,
        createdAt: createdAt,
      );
    }).where((c) => c.id.isNotEmpty && c.userId.isNotEmpty && c.content.isNotEmpty).toList(growable: false);
  }

  Future<void> _toggleLike(ReelFeedEntry item) async {
    if (item.mediaType == 'photo_song') {
      if (!_ensureSignedIn()) return;
      final uid = _firebaseUid!;
      final postId = item.itemId.trim();
      if (postId.isEmpty) {
        _showSnack('Photo post is missing an id.');
        return;
      }

      final currentlyLiked = _likedPhotoPostIds.contains(postId);
      try {
        if (currentlyLiked) {
          await Supabase.instance.client
              .from('photo_song_post_likes')
              .delete()
              .eq('post_id', postId)
              .eq('user_id', uid);
        } else {
          await Supabase.instance.client.from('photo_song_post_likes').upsert(
            <String, dynamic>{
              'post_id': postId,
              'user_id': uid,
            },
            onConflict: 'post_id,user_id',
          );
        }

        if (!mounted) return;
        setState(() {
          if (currentlyLiked) {
            _likedPhotoPostIds.remove(postId);
          } else {
            _likedPhotoPostIds.add(postId);
          }
        });

        _updateEntry(
          item.id,
          (current) => current.copyWith(
            likesCount: math.max(0, current.likesCount + (currentlyLiked ? -1 : 1)),
          ),
        );
      } catch (_) {
        _showSnack('Could not update like right now.');
      }
      return;
    }

    await _likeManager.toggleLike(
      item.id,
      fallbackCount: item.likesCount,
      onAuthRequired: () {
        widget.onAuthRequired?.call();
        _showSnack('Please sign in to like reels.');
      },
      onError: _showSnack,
    );
  }

  Future<void> _share(ReelFeedEntry item) async {
    await Clipboard.setData(ClipboardData(text: item.videoUrl));
    final uid = _firebaseUid;
    if (uid != null) {
      try {
        await _engagementRepo.recordShare(videoId: item.id, userId: uid);
      } catch (_) {
        // Keep UX smooth even if analytics write fails.
      }
    }
    _showSnack('Video link copied.');
  }

  Future<void> _toggleSavedQuick(ReelFeedEntry item) async {
    if (item.mediaType != 'video') {
      _showSnack('Save is available for videos right now.');
      return;
    }

    if (!_ensureSignedIn()) return;
    final uid = _firebaseUid!;
    final next = !_savedIds.contains(item.id);
    try {
      await _engagementRepo.setSaved(videoId: item.id, userId: uid, saved: next);
      if (!mounted) return;
      setState(() {
        if (next) {
          _savedIds.add(item.id);
        } else {
          _savedIds.remove(item.id);
        }
      });
      _showSnack(next ? 'Saved.' : 'Removed from saved.');
    } catch (_) {
      _showSnack('Could not update saved state.');
    }
  }

  Future<void> _openCommentsSheet(ReelFeedEntry item) async {
    if (item.mediaType == 'photo_song') {
      if (!_ensureSignedIn()) return;
      final uid = _firebaseUid!;
      final postId = item.itemId.trim();
      if (postId.isEmpty) {
        _showSnack('Photo post is missing an id.');
        return;
      }

      final inputController = TextEditingController();
      final comments = ValueNotifier<List<_PhotoPostComment>>(<_PhotoPostComment>[]);
      final posting = ValueNotifier<bool>(false);

      Future<void> loadComments() async {
        try {
          comments.value = await _listPhotoPostComments(postId);
        } catch (_) {
          _showSnack('Unable to load comments.');
        }
      }

      await loadComments();

      _PhotoPostComment? parseCommentFromRecord(Map<String, dynamic> row) {
        final id = (row['id'] ?? '').toString().trim();
        final userId = (row['user_id'] ?? '').toString().trim();
        final content = (row['content'] ?? '').toString().trim();
        final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString()) ?? DateTime.now().toUtc();
        if (id.isEmpty || userId.isEmpty || content.isEmpty) return null;
        return _PhotoPostComment(
          id: id,
          userId: userId,
          content: content,
          createdAt: createdAt,
        );
      }

      final commentsChannel = Supabase.instance.client
          .channel('photo_post_comments_sheet_$postId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'photo_song_post_comments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'post_id',
              value: postId,
            ),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                final row = payload.newRecord;
                final parsed = parseCommentFromRecord(row);
                if (parsed == null) return;
                final existing = comments.value;
                if (existing.any((c) => c.id == parsed.id)) return;
                comments.value = <_PhotoPostComment>[...existing, parsed];
                return;
              }

              if (payload.eventType == PostgresChangeEvent.delete) {
                final deletedId = (payload.oldRecord['id'] ?? '').toString().trim();
                if (deletedId.isEmpty) return;
                comments.value = comments.value.where((c) => c.id != deletedId).toList(growable: false);
              }
            },
          )
          .subscribe();

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Divider(height: 16),
                  Expanded(
                    child: ValueListenableBuilder<List<_PhotoPostComment>>(
                      valueListenable: comments,
                      builder: (context, value, child) {
                        if (value.isEmpty) {
                          return const Center(child: Text('No comments yet.'));
                        }
                        return ListView.builder(
                          itemCount: value.length,
                          itemBuilder: (context, idx) {
                            final c = value[idx];
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                              title: Text(c.content),
                              subtitle: Text(c.userId, maxLines: 1, overflow: TextOverflow.ellipsis),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: inputController,
                            maxLines: 3,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Write a post message',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: posting,
                          builder: (context, isPosting, child) {
                            return FilledButton(
                              onPressed: isPosting
                                  ? null
                                  : () async {
                                      final text = inputController.text.trim();
                                      if (text.isEmpty) return;
                                      posting.value = true;
                                      try {
                                        await Supabase.instance.client.from('photo_song_post_comments').insert({
                                          'post_id': postId,
                                          'user_id': uid,
                                          'content': text,
                                        });
                                        inputController.clear();
                                        await loadComments();
                                      } catch (_) {
                                        _showSnack('Could not post comment.');
                                      } finally {
                                        posting.value = false;
                                      }
                                    },
                              child: isPosting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Send'),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      comments.dispose();
      posting.dispose();
      inputController.dispose();
      Supabase.instance.client.removeChannel(commentsChannel);
      return;
    }

    final inputController = TextEditingController();
    final comments = ValueNotifier<List<ReelComment>>(<ReelComment>[]);
    final posting = ValueNotifier<bool>(false);

    Future<void> loadComments() async {
      try {
        comments.value = await _pagination.listComments(item.id);
      } catch (_) {
        _showSnack('Unable to load comments.');
      }
    }

    await loadComments();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Divider(height: 16),
                Expanded(
                  child: ValueListenableBuilder<List<ReelComment>>(
                    valueListenable: comments,
                    builder: (context, value, child) {
                      if (value.isEmpty) {
                        return const Center(child: Text('No comments yet.'));
                      }
                      return ListView.builder(
                        itemCount: value.length,
                        itemBuilder: (context, idx) {
                          final c = value[idx];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                            title: Text(c.content),
                            subtitle: Text(c.userId, maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputController,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Write a post message',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: posting,
                        builder: (context, isPosting, child) {
                          return FilledButton(
                            onPressed: isPosting
                                ? null
                                : () async {
                                    final text = inputController.text.trim();
                                    if (text.isEmpty) return;
                                    posting.value = true;
                                    try {
                                      await _pagination.addComment(reelId: item.id, content: text);
                                      inputController.clear();
                                      await loadComments();
                                      _updateEntry(
                                        item.id,
                                        (current) =>
                                            current.copyWith(commentsCount: current.commentsCount + 1),
                                      );
                                    } catch (e) {
                                      _showSnack('Could not post comment.');
                                    } finally {
                                      posting.value = false;
                                    }
                                  },
                            child: isPosting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Send'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    comments.dispose();
    posting.dispose();
    inputController.dispose();
  }

  Future<void> _openPostOptionsSheet(ReelFeedEntry item) async {
    final isVideoItem = item.mediaType == 'video';
    final isSaved = _savedIds.contains(item.id);
    final isFavorite = _favoriteIds.contains(item.id);
    final isFollowing = _followedCreatorIds.contains(item.userId);

    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        Widget option({
          required String value,
          required String label,
          IconData icon = Icons.chevron_right,
          Color? color,
        }) {
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: TextStyle(color: color)),
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              value: 'save',
              label: isSaved ? 'Unsave' : 'Save',
              icon: isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            ),
            option(value: 'remix', label: 'Remix', icon: Icons.auto_awesome_outlined),
            option(value: 'qr', label: 'QR code', icon: Icons.qr_code_2_rounded),
            option(
              value: 'favorite',
              label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
              icon: isFavorite ? Icons.favorite : Icons.favorite_border_rounded,
            ),
            option(
              value: 'unfollow',
              label: isFollowing ? 'Unfollow' : 'Follow',
              icon: isFollowing ? Icons.person_remove_alt_1_outlined : Icons.person_add_alt_1_outlined,
            ),
            option(value: 'why', label: "Why you're seeing this post", icon: Icons.info_outline_rounded),
            option(value: 'hide', label: 'Hide', icon: Icons.visibility_off_outlined),
            option(value: 'about', label: 'About this account', icon: Icons.account_circle_outlined),
            option(value: 'report', label: 'Report', icon: Icons.flag_outlined, color: Colors.redAccent),
            const SizedBox(height: 8),
          ],
        );
      },
    );

    if (choice == null) return;

    switch (choice) {
      case 'save':
        if (!isVideoItem) {
          _showSnack('Save is available for videos right now.');
          break;
        }
        if (!_ensureSignedIn()) return;
        final uid = _firebaseUid!;
        final next = !_savedIds.contains(item.id);
        try {
          await _engagementRepo.setSaved(videoId: item.id, userId: uid, saved: next);
          if (!mounted) return;
          setState(() {
            if (next) {
              _savedIds.add(item.id);
            } else {
              _savedIds.remove(item.id);
            }
          });
          _showSnack(next ? 'Saved.' : 'Removed from saved.');
        } catch (_) {
          _showSnack('Could not update saved state.');
        }
        break;
      case 'remix':
        if (!isVideoItem) {
          _showSnack('Remix is available for videos only.');
          break;
        }
        await _openRemixSheet(item);
        break;
      case 'qr':
        await Clipboard.setData(ClipboardData(text: item.videoUrl));
        _showSnack('Share link copied.');
        break;
      case 'favorite':
        if (!isVideoItem) {
          _showSnack('Favorites are available for videos right now.');
          break;
        }
        if (!_ensureSignedIn()) return;
        final uid = _firebaseUid!;
        final next = !_favoriteIds.contains(item.id);
        try {
          // Prefer dedicated favorites table if available.
          if (next) {
            await Supabase.instance.client.from('video_favorites').upsert(
              <String, dynamic>{'video_id': item.id, 'user_id': uid},
              onConflict: 'video_id,user_id',
            );
          } else {
            await Supabase.instance.client
                .from('video_favorites')
                .delete()
                .eq('video_id', item.id)
                .eq('user_id', uid);
          }
        } catch (_) {
          // Fallback to saves if favorites table does not exist.
          try {
            await _engagementRepo.setSaved(videoId: item.id, userId: uid, saved: next);
          } catch (_) {
            _showSnack('Could not update favorites.');
            return;
          }
        }

        if (!mounted) return;
        setState(() {
          if (next) {
            _favoriteIds.add(item.id);
          } else {
            _favoriteIds.remove(item.id);
          }
        });
        _showSnack(next ? 'Added to favorites.' : 'Removed from favorites.');
        break;
      case 'unfollow':
        if (!_ensureSignedIn()) return;
        final uid = _firebaseUid!;
        final currentlyFollowing = _followedCreatorIds.contains(item.userId);
        final nextFollowing = !currentlyFollowing;
        try {
          await _engagementRepo.setFollow(
            artistId: item.userId,
            userId: uid,
            following: nextFollowing,
          );
          if (!mounted) return;
          setState(() {
            if (nextFollowing) {
              _followedCreatorIds.add(item.userId);
            } else {
              _followedCreatorIds.remove(item.userId);
            }
          });
          _showSnack(nextFollowing ? 'Following.' : 'Unfollowed.');
        } catch (_) {
          _showSnack('Could not update follow state.');
        }
        break;
      case 'why':
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          builder: (ctx) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'You are seeing this post based on your recent watch time, likes, comments, and follows.',
              style: TextStyle(fontSize: 15),
            ),
          ),
        );
        break;
      case 'hide':
        if (!isVideoItem) {
          if (!mounted) return;
          setState(() {
            _items = _items.where((e) => e.id != item.id).toList(growable: false);
            if (_activeIndex >= _items.length) {
              _activeIndex = (_items.isEmpty ? 0 : _items.length - 1);
            }
          });
          _showSnack('Post hidden.');
          break;
        }
        if (!_ensureSignedIn()) return;
        final uid = _firebaseUid!;
        try {
          await _engagementRepo.setNotInterested(videoId: item.id, userId: uid, notInterested: true);
        } catch (_) {
          _showSnack('Could not hide this post right now.');
          return;
        }

        if (!mounted) return;
        setState(() {
          _items = _items.where((e) => e.id != item.id).toList(growable: false);
          if (_activeIndex >= _items.length) {
            _activeIndex = (_items.isEmpty ? 0 : _items.length - 1);
          }
        });
        _showSnack('Post hidden.');
        break;
      case 'about':
        widget.onOpenArtistProfile?.call(item.userId);
        break;
      case 'report':
        if (!isVideoItem) {
          _showSnack('Report for photo posts is coming soon.');
          break;
        }
        if (!_ensureSignedIn()) return;
        final uid = _firebaseUid!;
        try {
          await _engagementRepo.reportVideo(
            videoId: item.id,
            reason: 'other',
            reporterId: uid,
          );
          _showSnack('Report submitted.');
        } catch (_) {
          _showSnack('Could not submit report right now.');
        }
        break;
    }
  }

  Future<void> _openRemixSheet(ReelFeedEntry item) async {
    if (item.mediaType != 'video') {
      _showSnack('Remix is available for videos only.');
      return;
    }

    if (!_ensureSignedIn()) return;
    final uid = _firebaseUid!;

    final mode = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        Widget remixOption({
          required String value,
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return InkWell(
            onTap: () => Navigator.of(ctx).pop(value),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
              'How would you like your clip to play?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: remixOption(
                value: 'with_original',
                icon: Icons.view_carousel_outlined,
                title: 'Remix with original video',
                subtitle: 'Your clip and the original play in one remix flow.',
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: remixOption(
                value: 'after_original',
                icon: Icons.playlist_play_rounded,
                title: 'Sequence after original video',
                subtitle: 'Your clip plays right after the original video.',
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );

    if (mode == null) return;

    try {
      await Supabase.instance.client.from('video_remixes').insert(<String, dynamic>{
        'source_video_id': item.id,
        'user_id': uid,
        'status': mode,
      });
      _showSnack('Remix started.');
    } catch (_) {
      _showSnack('Could not start remix right now.');
    }
  }

  Future<void> _toggleFollowQuick(ReelFeedEntry item) async {
    if (!_ensureSignedIn()) return;
    final uid = _firebaseUid!;
    final currentlyFollowing = _followedCreatorIds.contains(item.userId);
    final nextFollowing = !currentlyFollowing;
    try {
      await _engagementRepo.setFollow(
        artistId: item.userId,
        userId: uid,
        following: nextFollowing,
      );
      if (!mounted) return;
      setState(() {
        if (nextFollowing) {
          _followedCreatorIds.add(item.userId);
        } else {
          _followedCreatorIds.remove(item.userId);
        }
      });
      _showSnack(nextFollowing ? 'Following.' : 'Unfollowed.');
    } catch (_) {
      _showSnack('Could not update follow state.');
    }
  }

  void _useThisSound(ReelFeedEntry item) {
    final songId = (item.songId ?? '').trim();
    if (songId.isEmpty) {
      _showSnack('No sound attached to this post.');
      return;
    }
    if (!_ensureSignedIn()) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoSongPostMockupScreen(
          role: UserRole.consumer,
          initialSongId: songId,
          initialSongStartSeconds: item.songStartSeconds,
          initialSongDurationSeconds: item.songDurationSeconds,
        ),
      ),
    );
  }

  Widget _buildFeedItem(BuildContext context, int index) {
    final item = _items[index];
    final likeState = _likeManager.stateFor(item.id, fallbackCount: item.likesCount);
    final isSaved = _savedIds.contains(item.id);
    final isFollowing = _followedCreatorIds.contains(item.userId);
    final mediaPadding = MediaQuery.paddingOf(context);
    final safeTop = mediaPadding.top;
    final safeBottom = mediaPadding.bottom;
    final displayHandle = (() {
      final username = (item.creatorUsername ?? '').trim();
      if (username.isNotEmpty) return '@$username';
      final name = (item.creatorDisplayName ?? '').trim();
      if (name.isNotEmpty) return name;
      return '@artist';
    })();
    final caption = (item.caption ?? '').trim().isNotEmpty
        ? item.caption!.trim()
        : '${item.musicTitle ?? 'Untitled'} - ${item.musicArtist ?? 'Unknown'}';
    final audioLabel = (item.musicTitle ?? '').trim().isNotEmpty
        ? '${item.musicTitle}${(item.musicArtist ?? '').trim().isEmpty ? '' : ' • ${item.musicArtist}'}'
        : 'Original audio';

    Widget actionButton({
      required IconData icon,
      required VoidCallback onTap,
      String? label,
      Color? iconColor,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, size: 26, color: iconColor ?? Colors.white),
                ),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final isVideoEntry = item.mediaType == 'video';
    final isPhotoEntry = item.mediaType == 'photo_song';
    final isLiked = isPhotoEntry ? _likedPhotoPostIds.contains(item.itemId) : likeState.isLikedByMe;
    final likeCount = isPhotoEntry ? item.likesCount : likeState.likesCount;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _showOverlayControls = !_showOverlayControls;
            });
          },
          onDoubleTap: () {
            HapticFeedback.lightImpact();
            if (!isLiked) {
              unawaited(_toggleLike(item));
            }
          },
          child: isVideoEntry
              ? ReelVideoPlayer(
                  reelId: item.id,
                  videoUrl: item.videoUrl,
                  thumbnailUrl: item.thumbnailUrl,
                  isActive: _activeIndex == index,
                  isMuted: _muted,
                  sessionId: _sessionId,
                  onWatchMoreReels: () async {
                    final next = index + 1;
                    if (next < _items.length) {
                      await _pageController.animateToPage(
                        next,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                      );
                      return;
                    }
                    _showSnack('No more reels right now.');
                  },
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.grey.shade900,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 4 / 5,
                          child: Image.network(
                            item.videoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'PHOTO + SONG',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0.0, 0.24, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          ignoring: !_showOverlayControls,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _showOverlayControls ? 1 : 0,
            child: Stack(
              children: [
                Positioned(
                  top: safeTop + 10,
                  left: 12,
                  right: 12,
                  child: SizedBox(
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Navigator.of(context).canPop()
                              ? Material(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => Navigator.of(context).maybePop(),
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                                    ),
                                  ),
                                )
                              : const SizedBox(width: 40, height: 40),
                        ),
                          Text(
                          isVideoEntry ? 'Reels' : 'Photo Posts',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.38),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final nextMuted = !_muted;
                                unawaited(_setMuted(nextMuted));
                                if (nextMuted) {
                                  _stopPhotoSongPlayback();
                                } else {
                                  _handleActiveItemChanged();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: safeBottom + 90,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      actionButton(
                        icon: isLiked ? Icons.favorite : Icons.favorite_border,
                        iconColor: isLiked ? Colors.redAccent : Colors.white,
                        label: _compactCount(likeCount),
                        onTap: () => unawaited(_toggleLike(item)),
                      ),
                      actionButton(
                        icon: Icons.mode_comment_outlined,
                        label: _compactCount(item.commentsCount),
                        onTap: () => unawaited(_openCommentsSheet(item)),
                      ),
                      actionButton(
                        icon: Icons.send_rounded,
                        onTap: () => unawaited(_share(item)),
                      ),
                      actionButton(
                        icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                        onTap: () => unawaited(_toggleSavedQuick(item)),
                      ),
                      actionButton(
                        icon: Icons.more_horiz,
                        onTap: () => _openPostOptionsSheet(item),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 90,
                  bottom: safeBottom + 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => widget.onOpenArtistProfile?.call(item.userId),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFF2A2A2A),
                              child: Icon(Icons.person, size: 15, color: Colors.white70),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                displayHandle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.tonal(
                              onPressed: () => _toggleFollowQuick(item),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(70, 30),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(isFollowing ? 'Following' : 'Follow'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              audioLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if ((item.songId ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () => _useThisSound(item),
                          icon: const Icon(Icons.music_note_rounded, size: 18),
                          label: const Text('Use this sound'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            backgroundColor: Colors.white.withValues(alpha: 0.18),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_loadError != null && _items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load reels', style: TextStyle(color: Colors.white, fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(_loadError!, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => unawaited(_refresh()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height,
                child: const Center(
                  child: Text(
                    'No reels yet. Pull to refresh.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _items.length,
            onPageChanged: (index) {
              _activeIndex = index;
              _syncScopedRealtime();
              unawaited(_loadMoreIfNeeded());
              _handleActiveItemChanged();
              setState(() {});
            },
            itemBuilder: _buildFeedItem,
          ),
          if (_loadingMore)
            const Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
