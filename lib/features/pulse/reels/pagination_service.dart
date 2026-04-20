import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class ReelFeedEntry {
  const ReelFeedEntry({
    required this.id,
    required this.itemId,
    required this.userId,
    required this.videoUrl,
    required this.createdAt,
    this.mediaType = 'video',
    this.thumbnailUrl,
    this.caption,
    this.musicTitle,
    this.musicArtist,
    this.songId,
    this.songStartSeconds,
    this.songDurationSeconds,
    this.creatorUsername,
    this.creatorDisplayName,
    this.creatorAvatarUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.viewsCount = 0,
    this.isLikedByMe = false,
  });

  final String id;
  final String itemId;
  final String userId;
  final String videoUrl;
  final String mediaType;
  final String? thumbnailUrl;
  final String? caption;
  final String? musicTitle;
  final String? musicArtist;
  final String? songId;
  final int? songStartSeconds;
  final int? songDurationSeconds;
  final String? creatorUsername;
  final String? creatorDisplayName;
  final String? creatorAvatarUrl;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int viewsCount;
  final bool isLikedByMe;

  ReelFeedEntry copyWith({
    String? id,
    String? itemId,
    String? userId,
    String? videoUrl,
    String? mediaType,
    String? thumbnailUrl,
    String? caption,
    String? musicTitle,
    String? musicArtist,
    String? songId,
    int? songStartSeconds,
    int? songDurationSeconds,
    String? creatorUsername,
    String? creatorDisplayName,
    String? creatorAvatarUrl,
    DateTime? createdAt,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    int? viewsCount,
    bool? isLikedByMe,
  }) {
    return ReelFeedEntry(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      userId: userId ?? this.userId,
      videoUrl: videoUrl ?? this.videoUrl,
      mediaType: mediaType ?? this.mediaType,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      caption: caption ?? this.caption,
      musicTitle: musicTitle ?? this.musicTitle,
      musicArtist: musicArtist ?? this.musicArtist,
      songId: songId ?? this.songId,
      songStartSeconds: songStartSeconds ?? this.songStartSeconds,
      songDurationSeconds: songDurationSeconds ?? this.songDurationSeconds,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      creatorDisplayName: creatorDisplayName ?? this.creatorDisplayName,
      creatorAvatarUrl: creatorAvatarUrl ?? this.creatorAvatarUrl,
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
    );
  }

  static ReelFeedEntry? fromMap(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final userId = (row['user_id'] ?? '').toString().trim();
    final videoUrl = (row['video_url'] ?? '').toString().trim();
    final createdAtRaw = (row['created_at'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse(createdAtRaw);

    if (id.isEmpty || userId.isEmpty || videoUrl.isEmpty || createdAt == null) {
      return null;
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return ReelFeedEntry(
      id: id,
      itemId: id,
      userId: userId,
      videoUrl: videoUrl,
      mediaType: 'video',
      thumbnailUrl: (row['thumbnail_url'] ?? '').toString().trim().isEmpty
          ? null
          : (row['thumbnail_url'] ?? '').toString().trim(),
      caption: (row['caption'] ?? '').toString().trim().isEmpty
          ? null
          : (row['caption'] ?? '').toString().trim(),
      musicTitle: (row['music_title'] ?? '').toString().trim().isEmpty
          ? null
          : (row['music_title'] ?? '').toString().trim(),
      musicArtist: (row['music_artist'] ?? '').toString().trim().isEmpty
          ? null
          : (row['music_artist'] ?? '').toString().trim(),
        creatorUsername: (row['creator_username'] ?? '').toString().trim().isEmpty
          ? null
          : (row['creator_username'] ?? '').toString().trim(),
        creatorDisplayName: (row['creator_display_name'] ?? '').toString().trim().isEmpty
          ? null
          : (row['creator_display_name'] ?? '').toString().trim(),
        creatorAvatarUrl: (row['creator_avatar_url'] ?? '').toString().trim().isEmpty
          ? null
          : (row['creator_avatar_url'] ?? '').toString().trim(),
      createdAt: createdAt,
      likesCount: parseInt(row['likes_count']),
      commentsCount: parseInt(row['comments_count']),
      sharesCount: parseInt(row['shares_count']),
      viewsCount: parseInt(row['views_count']),
    );
  }
}

class ReelCursor {
  const ReelCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

class ReelPageResult {
  const ReelPageResult({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ReelFeedEntry> items;
  final ReelCursor? nextCursor;
  final bool hasMore;
}

class ReelComment {
  const ReelComment({
    required this.id,
    required this.reelId,
    required this.userId,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String reelId;
  final String userId;
  final String content;
  final DateTime createdAt;

  static ReelComment? fromMap(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final reelId = (row['reel_id'] ?? '').toString().trim();
    final userId = (row['user_id'] ?? '').toString().trim();
    final content = (row['content'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (id.isEmpty || reelId.isEmpty || userId.isEmpty || content.isEmpty || createdAt == null) {
      return null;
    }
    return ReelComment(
      id: id,
      reelId: reelId,
      userId: userId,
      content: content,
      createdAt: createdAt,
    );
  }
}

class ReelPaginationService {
  ReelPaginationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int defaultPageSize = 10;
  static const Duration _networkTimeout = Duration(seconds: 10);

  Future<T> _retryWithBackoff<T>(Future<T> Function() task) async {
    Object? lastError;
    var delay = const Duration(milliseconds: 350);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await task().timeout(_networkTimeout);
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        final lower = e.toString().toLowerCase();
        final isTransient =
            lower.contains('timeout') || lower.contains('network') || lower.contains('socket');
        if (!isTransient) rethrow;
        lastError = e;
      }

      if (attempt < 2) {
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }

    throw lastError ?? StateError('Reel request failed');
  }

  Future<ReelPageResult> fetchPage({
    ReelCursor? cursor,
    int limit = defaultPageSize,
  }) async {
    final safeLimit = limit.clamp(1, 30);

    List<ReelFeedEntry> items = const <ReelFeedEntry>[];
    var usedFallback = false;

    try {
      final rows = await _retryWithBackoff<List<dynamic>>(() async {
        dynamic query = _client
            .from('reels')
            .select(
              'id,user_id,video_url,thumbnail_url,caption,music_title,music_artist,'
              'likes_count,comments_count,shares_count,views_count,created_at',
            )
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(safeLimit);

        if (cursor != null) {
          final created = cursor.createdAt.toUtc().toIso8601String();
          query = query.or('created_at.lt.$created,and(created_at.eq.$created,id.lt.${cursor.id})');
        }

        return await query;
      });

      items = rows
          .whereType<Map>()
          .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
          .map(ReelFeedEntry.fromMap)
          .whereType<ReelFeedEntry>()
          .toList(growable: false);

      // If reels table exists but has no data yet, use videos as a temporary feed source.
      if (items.isEmpty) {
        usedFallback = true;
        items = await _fetchFromVideosFallback(cursor: cursor, limit: safeLimit);
      }
    } catch (_) {
      usedFallback = true;
      items = await _fetchFromVideosFallback(cursor: cursor, limit: safeLimit);
    }

    // Blend in photo+song posts so they appear in the same consumer feed stream.
    try {
      final photoPosts = await _fetchFromPhotoSongPosts(cursor: cursor, limit: safeLimit);
      if (photoPosts.isNotEmpty) {
        final merged = <ReelFeedEntry>[...items, ...photoPosts]
          ..sort((a, b) {
            final cmp = b.createdAt.compareTo(a.createdAt);
            if (cmp != 0) return cmp;
            return b.id.compareTo(a.id);
          });
        items = merged.take(safeLimit).toList(growable: false);
      }
    } catch (_) {
      // Keep feed usable even if photo posts query fails in some environments.
    }

    if (items.isNotEmpty) {
      items = await _attachProfileHandles(items);
    }

    final hasMore = items.length == safeLimit;
    final nextCursor = items.isEmpty
        ? null
        : ReelCursor(createdAt: items.last.createdAt, id: items.last.id);

    // When using fallback rows, cursor paging is still based on created_at/id ordering.
    return ReelPageResult(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore && (usedFallback || items.isNotEmpty),
    );
  }

  Future<List<ReelFeedEntry>> _fetchFromPhotoSongPosts({
    ReelCursor? cursor,
    required int limit,
  }) async {
    final rows = await _retryWithBackoff<List<dynamic>>(() async {
      dynamic query = _client
          .from('photo_song_posts')
          .select('id,creator_uid,image_url,song_id,song_start,song_duration,caption,likes_count,comments_count,created_at')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);

      if (cursor != null) {
        final created = cursor.createdAt.toUtc().toIso8601String();
        query = query.or('created_at.lt.$created,and(created_at.eq.$created,id.lt.${cursor.id})');
      }

      return await query;
    });

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final out = <ReelFeedEntry>[];

    final songIds = <String>{};
    for (final raw in rows.whereType<Map>()) {
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final songId = (row['song_id'] ?? '').toString().trim();
      if (songId.isNotEmpty) songIds.add(songId);
    }

    final songMetaById = <String, Map<String, dynamic>>{};
    if (songIds.isNotEmpty) {
      try {
        final songRows = await _client
            .from('songs')
            .select('id,title,artist')
            .inFilter('id', songIds.toList(growable: false))
            .limit(songIds.length);

        for (final raw in (songRows as List<dynamic>).whereType<Map>()) {
          final row = raw.map((key, value) => MapEntry(key.toString(), value));
          final id = (row['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          songMetaById[id] = row;
        }
      } catch (_) {
        // Metadata is best-effort; playback can still resolve by id later.
      }
    }

    for (final raw in rows.whereType<Map>()) {
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final id = (row['id'] ?? '').toString().trim();
      final userId = (row['creator_uid'] ?? '').toString().trim();
      final imageUrl = (row['image_url'] ?? '').toString().trim();
      final songId = (row['song_id'] ?? '').toString().trim();
      final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString());
      if (id.isEmpty || userId.isEmpty || imageUrl.isEmpty || createdAt == null) continue;

      final songStartSeconds = parseInt(row['song_start']);
      final songDurationSeconds = parseInt(row['song_duration']);
      final meta = songId.isEmpty ? null : songMetaById[songId];
      final musicTitle = (meta?['title'] ?? '').toString().trim();
      final musicArtist = (meta?['artist'] ?? '').toString().trim();

      out.add(
        ReelFeedEntry(
          id: 'photo_$id',
          itemId: id,
          userId: userId,
          videoUrl: imageUrl,
          mediaType: 'photo_song',
          thumbnailUrl: imageUrl,
          caption: (row['caption'] ?? '').toString().trim().isEmpty
              ? null
              : (row['caption'] ?? '').toString().trim(),
          musicTitle: musicTitle.isEmpty ? 'Photo + Song' : musicTitle,
          musicArtist: musicArtist.isEmpty ? null : musicArtist,
          songId: songId.isEmpty ? null : songId,
          songStartSeconds: songStartSeconds <= 0 ? 0 : songStartSeconds,
          songDurationSeconds: songDurationSeconds <= 0 ? null : songDurationSeconds,
          createdAt: createdAt,
          likesCount: parseInt(row['likes_count']),
          commentsCount: parseInt(row['comments_count']),
          sharesCount: 0,
          viewsCount: 0,
        ),
      );
    }

    return out;
  }

  Future<List<ReelFeedEntry>> _attachProfileHandles(List<ReelFeedEntry> items) async {
    final ids = items
        .map((e) => e.userId.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ids.isEmpty) return items;

    try {
      final rows = await _client
          .from('profiles')
          .select('id,username,display_name,avatar_url')
          .inFilter('id', ids)
          .limit(500);

      final byId = <String, Map<String, dynamic>>{};
      for (final raw in rows.whereType<Map>()) {
        final row = raw.map((key, value) => MapEntry(key.toString(), value));
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byId[id] = row;
      }

      return items.map((item) {
        final profile = byId[item.userId];
        if (profile == null) return item;
        return item.copyWith(
          creatorUsername: (profile['username'] ?? '').toString().trim().isEmpty
              ? item.creatorUsername
              : (profile['username'] ?? '').toString().trim(),
          creatorDisplayName: (profile['display_name'] ?? '').toString().trim().isEmpty
              ? item.creatorDisplayName
              : (profile['display_name'] ?? '').toString().trim(),
          creatorAvatarUrl: (profile['avatar_url'] ?? '').toString().trim().isEmpty
              ? item.creatorAvatarUrl
              : (profile['avatar_url'] ?? '').toString().trim(),
        );
      }).toList(growable: false);
    } catch (_) {
      // Continue to artist fallback.
    }

    try {
      final artistsById = await _client
          .from('artists')
          .select('id,user_id,firebase_uid,username,display_name,stage_name,artist_name,name,profile_image,avatar_url')
          .inFilter('id', ids)
          .limit(500);

      final artistsByUserId = await _client
          .from('artists')
          .select('id,user_id,firebase_uid,username,display_name,stage_name,artist_name,name,profile_image,avatar_url')
          .inFilter('user_id', ids)
          .limit(500);

      final artistsByFirebaseUid = await _client
          .from('artists')
          .select('id,user_id,firebase_uid,username,display_name,stage_name,artist_name,name,profile_image,avatar_url')
          .inFilter('firebase_uid', ids)
          .limit(500);

      final rows = <dynamic>[
        ...artistsById,
        ...artistsByUserId,
        ...artistsByFirebaseUid,
      ];

      String? pickName(Map<String, dynamic> row) {
        const keys = <String>[
          'username',
          'display_name',
          'stage_name',
          'artist_name',
          'name',
        ];
        for (final key in keys) {
          final value = (row[key] ?? '').toString().trim();
          if (value.isNotEmpty) return value;
        }
        return null;
      }

      final byAny = <String, Map<String, dynamic>>{};
      for (final raw in rows.whereType<Map>()) {
        final row = raw.map((key, value) => MapEntry(key.toString(), value));
        for (final key in <String>['id', 'user_id', 'firebase_uid']) {
          final value = (row[key] ?? '').toString().trim();
          if (value.isNotEmpty) {
            byAny[value] = row;
          }
        }
      }

      return items.map((item) {
        final artist = byAny[item.userId];
        if (artist == null) return item;
        final picked = pickName(artist);
        return item.copyWith(
          creatorUsername: item.creatorUsername ?? picked,
          creatorDisplayName: item.creatorDisplayName ?? picked,
          creatorAvatarUrl: item.creatorAvatarUrl ??
              ((artist['profile_image'] ?? artist['avatar_url'] ?? '').toString().trim().isEmpty
                  ? null
                  : (artist['profile_image'] ?? artist['avatar_url']).toString().trim()),
        );
      }).toList(growable: false);
    } catch (_) {
      return items;
    }
  }

  Future<List<ReelFeedEntry>> _fetchFromVideosFallback({
    ReelCursor? cursor,
    required int limit,
  }) async {
    final rows = await _retryWithBackoff<List<dynamic>>(() async {
      dynamic query = _client
          .from('videos')
          .select('*')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);

      if (cursor != null) {
        final created = cursor.createdAt.toUtc().toIso8601String();
        query = query.or('created_at.lt.$created,and(created_at.eq.$created,id.lt.${cursor.id})');
      }

      return await query;
    });

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final out = <ReelFeedEntry>[];
    for (final raw in rows.whereType<Map>()) {
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final id = (row['id'] ?? '').toString().trim();
      final userId = ((row['user_id'] ?? row['creator_uid'] ?? row['uploader_id'] ?? row['artist_id']) ?? '')
        .toString()
        .trim();
      final videoUrl =
        ((row['video_url'] ?? row['url'] ?? row['video'] ?? row['stream_url']) ?? '').toString().trim();
      final songId = (row['song_id'] ?? '').toString().trim();
      final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString());
      final isActive = row['is_active'];
      final isApproved = row['approved'];
      final allowedByActive = isActive == null || isActive == true || '$isActive' == '1';
      final allowedByApproved = isApproved == null || isApproved == true || '$isApproved' == '1';

      if (!allowedByActive || !allowedByApproved) continue;
      if (id.isEmpty || userId.isEmpty || videoUrl.isEmpty || createdAt == null) continue;

      out.add(
        ReelFeedEntry(
          id: id,
          itemId: id,
          userId: userId,
          videoUrl: videoUrl,
        mediaType: 'video',
        thumbnailUrl: ((row['thumbnail_url'] ?? row['thumbnail'] ?? row['thumb_url'] ?? row['image_url']) ?? '')
            .toString()
            .trim()
            .isEmpty
              ? null
          : ((row['thumbnail_url'] ?? row['thumbnail'] ?? row['thumb_url'] ?? row['image_url']) ?? '')
            .toString()
            .trim(),
          caption: (row['caption'] ?? '').toString().trim().isEmpty
              ? null
          : (row['caption'] ?? row['description'] ?? '').toString().trim(),
        musicTitle: ((row['title'] ?? row['name']) ?? '').toString().trim().isEmpty
              ? null
          : ((row['title'] ?? row['name']) ?? '').toString().trim(),
          musicArtist: (row['artist_id'] ?? '').toString().trim().isEmpty
              ? null
          : ((row['artist_id'] ?? row['creator_uid'] ?? row['uploader_id']) ?? '').toString().trim(),
          songId: songId.isEmpty ? null : songId,
          songStartSeconds: parseInt(row['song_start']) <= 0 ? 0 : parseInt(row['song_start']),
          songDurationSeconds:
              parseInt(row['song_duration']) <= 0 ? null : parseInt(row['song_duration']),
          createdAt: createdAt,
        likesCount: parseInt(row['likes_count'] ?? row['likes']),
        commentsCount: parseInt(row['comments_count'] ?? row['comments']),
        viewsCount: parseInt(row['views_count'] ?? row['views']),
        ),
      );
    }

    return out;
  }

  Future<List<ReelComment>> listComments(String reelId, {int limit = 50}) async {
    final trimmedId = reelId.trim();
    if (trimmedId.isEmpty) return const <ReelComment>[];

    final rows = await _retryWithBackoff<List<dynamic>>(() {
      return _client
          .from('reel_comments')
          .select('id,reel_id,user_id,content,created_at')
          .eq('reel_id', trimmedId)
          .order('created_at', ascending: true)
          .limit(limit.clamp(1, 200));
    });

    return rows
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .map(ReelComment.fromMap)
        .whereType<ReelComment>()
        .toList(growable: false);
  }

  Future<void> addComment({required String reelId, required String content}) async {
    final uid = _client.auth.currentUser?.id;
    final trimmedId = reelId.trim();
    final trimmedContent = content.trim();
    if (uid == null || trimmedId.isEmpty || trimmedContent.isEmpty) {
      throw StateError('Sign in required');
    }

    await _retryWithBackoff<void>(() async {
      await _client.from('reel_comments').insert({
        'reel_id': trimmedId,
        'user_id': uid,
        'content': trimmedContent,
        'parent_id': null,
      });
    });
  }

  Future<void> recordImpression({
    required String reelId,
    required int watchDuration,
    required bool completed,
    required String sessionId,
  }) async {
    final trimmed = reelId.trim();
    if (trimmed.isEmpty || watchDuration <= 0) return;

    await _client.from('reel_impressions').insert({
      'reel_id': trimmed,
      'user_id': _client.auth.currentUser?.id,
      'session_id': sessionId,
      'watch_duration': watchDuration,
      'completed': completed,
    });
  }
}
