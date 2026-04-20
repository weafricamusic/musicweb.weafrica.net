import 'package:flutter/foundation.dart';

import '../../app/config/supabase_env.dart';

@immutable
class Track {
  const Track({
    required this.title,
    required this.artist,
    this.id,
    this.audioUri,
    this.artworkUri,
    this.duration,
    this.country,
    this.genre,
    this.language,
    this.album,
    this.year,
    this.createdAt,
    this.isExclusive = false,
    this.isPromoted = false,
    this.promotionPlan,
    this.promotionEndsAt,
  });

  final String? id;
  final String title;
  final String artist;
  final Uri? audioUri;
  final Uri? artworkUri;
  final Duration? duration;
  final String? country;
  final String? genre;
  final String? language;
  final String? album;
  final int? year;
  final DateTime? createdAt;
  final bool isExclusive;
  final bool isPromoted;
  final String? promotionPlan;
  final DateTime? promotionEndsAt;

  String? get promotionBadgeLabel {
    if (!isPromoted) return null;
    final plan = (promotionPlan ?? '').trim().toLowerCase();
    if (plan == 'premium') return 'PROMOTED';
    if (plan == 'pro') return 'BOOSTED';
    return 'SPONSORED';
  }

  factory Track.fromSupabase(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final title = (row['title'] ?? '').toString();
    String artist = (row['artist'] ?? '').toString();
    if (artist.trim().isEmpty) {
      final embedded = row['artists'];
      if (embedded is Map) {
        artist = (embedded['name'] ?? embedded['stage_name'] ?? embedded['artist_name'] ?? '').toString();
      } else if (embedded is List && embedded.isNotEmpty) {
        final first = embedded.first;
        if (first is Map) {
          artist = (first['name'] ?? first['stage_name'] ?? first['artist_name'] ?? '').toString();
        }
      }
    }
    if (artist.trim().isEmpty) artist = 'Unknown Artist';

    const artworkCandidateKeys = <String>[
      'artwork_url',
      'artworkUrl',
      'artwork',
      'artwork_path',
      'artworkPath',
      'thumbnail_url',
      'thumbnailUrl',
      'thumbnail',
      'thumbnail_path',
      'thumbnailPath',
      'image_url',
      'imageUrl',
      'image_path',
      'imagePath',
      'cover_url',
      'coverUrl',
      'cover',
      'cover_path',
      'coverPath',
      'photo_url',
      'photoUrl',
      'picture_url',
      'pictureUrl',
    ];

    final audioUrlRaw = row['audio_url'] ?? row['audioUrl'] ?? row['url'];
    final audioUrl = _resolvePublicUrl(audioUrlRaw?.toString(), bucket: 'songs');

    String? artworkKeyUsed;
    Object? artworkUrlRaw;
    for (final key in artworkCandidateKeys) {
      final v = row[key];
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) continue;
      artworkKeyUsed = key;
      artworkUrlRaw = v;
      break;
    }

    final artworkUrl = _resolvePublicUrl(artworkUrlRaw?.toString(), bucket: 'song-thumbnails');

    // DEBUG: Artwork logging disabled to prevent spam in lists
    // if (kDebugMode) {
    //   final rawString = artworkUrlRaw?.toString() ?? '';
    //   final rawPreview = rawString.length > 100 ? '${rawString.substring(0, 100)}...' : (rawString.isEmpty ? '(empty)' : rawString);
    //   final resolvedPreview = artworkUrl == null
    //       ? 'NULL'
    //       : (artworkUrl.length > 100 ? '${artworkUrl.substring(0, 100)}...' : artworkUrl);
    //   debugPrint('📀 Track "$title": artworkKey=${artworkKeyUsed ?? '(none)'} raw=$rawPreview');
    //   debugPrint('   resolvedArtwork=$resolvedPreview');
    // }
    // Uncomment + call Track.resetDebugTrackCount() to enable temporarily:
    // if (kDebugMode && _debugTrackCount++ < 50) { ... }

    final durationMsRaw = row['duration_ms'] ?? row['durationMs'];
    final durationMs = durationMsRaw is num
        ? durationMsRaw.toInt()
        : int.tryParse(durationMsRaw?.toString() ?? '');

    final albumRaw = row['album'] ??
        row['album_title'] ??
        row['albumTitle'] ??
        row['album_name'] ??
        row['albumName'];
    final album = albumRaw?.toString().trim();

    final yearRaw = row['year'] ?? row['release_year'] ?? row['releaseYear'];
    final year = yearRaw is num ? yearRaw.toInt() : int.tryParse(yearRaw?.toString() ?? '');

    DateTime? createdAt;
    final createdAtRaw = row['created_at'] ?? row['createdAt'];
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw.toString());
    }

    DateTime? promotionEndsAt;
    final promotionEndsRaw =
        row['promotion_end_date'] ?? row['promotion_ends_at'] ?? row['end_date'];
    if (promotionEndsRaw != null) {
      promotionEndsAt = DateTime.tryParse(promotionEndsRaw.toString());
    }

    bool parseBool(dynamic raw) {
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      final s = raw?.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }

    final isExclusive = parseBool(
      row['is_exclusive'] ?? row['exclusive'] ?? row['exclusive_content'],
    );
    final isPromoted = parseBool(
      row['is_promoted'] ?? row['promoted'] ?? row['sponsored'],
    );
    final promotionPlan = (row['promotion_plan'] ?? row['plan'])?.toString().trim();

    return Track(
      id: id,
      title: title,
      artist: artist,
      audioUri: _parseUriOrNull(audioUrl),
      artworkUri:
          _parseUriOrNull(artworkUrl),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      country: row['country']?.toString(),
      genre: row['genre']?.toString(),
      language: row['language']?.toString(),
      album: (album == null || album.isEmpty) ? null : album,
      year: year,
      createdAt: createdAt,
      isExclusive: isExclusive,
      isPromoted: isPromoted,
      promotionPlan: (promotionPlan == null || promotionPlan.isEmpty)
          ? null
          : promotionPlan,
      promotionEndsAt: promotionEndsAt,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artist': artist,
      'audio_url': audioUri?.toString(),
      'artwork_url': artworkUri?.toString(),
      'duration_ms': duration?.inMilliseconds,
      'country': country,
      'genre': genre,
      'language': language,
      'album': album,
      'year': year,
      'created_at': createdAt?.toIso8601String(),
      'is_exclusive': isExclusive,
      'is_promoted': isPromoted,
      'promotion_plan': promotionPlan,
      'promotion_end_date': promotionEndsAt?.toIso8601String(),
    };
  }

  // Debug counter for temporary in-list logging. Kept as a class-level
  // static so it can be referenced from debug code across files.
  static int _debugTrackCount = 0;
  static void resetDebugTrackCount() => _debugTrackCount = 0;

  static Track fromCacheMap(Map<String, dynamic> map) {
    // Cache schema intentionally mirrors common Supabase columns.
    return Track.fromSupabase(map);
  }

  static Uri? _parseUriOrNull(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      return Uri.parse(trimmed);
    } catch (_) {
      // Last-resort: only replace literal spaces (avoid re-encoding %xx).
      final spaceFixed = trimmed.replaceAll(' ', '%20');
      try {
        return Uri.parse(spaceFixed);
      } catch (_) {
        return null;
      }
    }
  }

  static String? _resolvePublicUrl(String? raw, {required String bucket}) {
    if (raw == null) return null;
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Some DB rows are missing the scheme (e.g. `<ref>.supabase.co/storage/...`).
    // Treat these as HTTPS URLs.
    if (!trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://') &&
        (trimmed.startsWith('//') ||
            trimmed.contains('.supabase.co/') ||
            trimmed.contains('.functions.supabase.co/'))) {
      trimmed = trimmed.startsWith('//') ? 'https:$trimmed' : 'https://$trimmed';
    }

    // Strip common wrapping quotes from CSV/SQL imports.
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
      if (trimmed.isEmpty) return null;
    }

    trimmed = trimmed.replaceAll('%3CSUPABASE_URL%3E', '<SUPABASE_URL>');

    while (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }

    final base = SupabaseEnv.supabaseUrl;
    if (trimmed.contains('<SUPABASE_URL>') && base.isNotEmpty) {
      trimmed = trimmed.replaceAll('<SUPABASE_URL>', base);
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      trimmed = _sanitizeAbsoluteUrl(trimmed);

      // Normalize common Supabase storage URL variant missing `/public/`.
      if (trimmed.contains('/storage/v1/object/') &&
          !trimmed.contains('/storage/v1/object/public/') &&
          !trimmed.contains('/storage/v1/object/sign/')) {
        trimmed = trimmed.replaceFirst(
          '/storage/v1/object/',
          '/storage/v1/object/public/',
        );
      }

      if (base.isNotEmpty) {
        final doublePrefix = '$base/storage/v1/object/public/';
        final duplicate = '$doublePrefix$base/storage/v1/object/public/';
        if (trimmed.startsWith(duplicate)) {
          trimmed = trimmed.replaceFirst(duplicate, doublePrefix);
        }
      }
      return trimmed;
    }

    if (base.isEmpty) return trimmed;

    // Relative Supabase storage path.
    // Examples:
    // - storage/v1/object/public/songs/path.mp3
    // - storage/v1/object/songs/path.mp3
    if (trimmed.startsWith('storage/v1/object/')) {
      var path = trimmed;
      if (!path.startsWith('storage/v1/object/public/') &&
          !path.startsWith('storage/v1/object/sign/')) {
        path = path.replaceFirst(
          'storage/v1/object/',
          'storage/v1/object/public/',
        );
      }
      return '$base/$path';
    }

    if (trimmed.startsWith('storage/v1/object/public/')) {
      return '$base/$trimmed';
    }

    bool startsWithKnownBucket(String value) {
      return value.startsWith('song_thumbnails/') ||
          value.startsWith('song-thumbnails/') ||
          value.startsWith('songs/') ||
          value.startsWith('thumbnails/') ||
          value.startsWith('media/') ||
          value.startsWith('${bucket.trim()}/');
    }

    if (trimmed.contains('/')) {
      final encoded = trimmed
          .split('/')
          .map((segment) => segment.contains('%') ? segment : Uri.encodeComponent(segment))
          .join('/');

      // If the value already includes a bucket prefix, keep it but normalize
      // bucket naming differences.
      if (startsWithKnownBucket(trimmed)) {
        final firstSlash = encoded.indexOf('/');
        if (firstSlash > 0) {
          final b = encoded.substring(0, firstSlash);
          final rest = encoded.substring(firstSlash + 1);
          // Do NOT rewrite bucket ids here; different Supabase instances may
          // use either `song_thumbnails` or `song-thumbnails`.
          return '$base/storage/v1/object/public/$b/$rest';
        }
        return '$base/storage/v1/object/public/$encoded';
      }

      // Otherwise treat it as an object path inside the provided bucket.
      final bucketTrimmed = bucket.trim();
      return '$base/storage/v1/object/public/$bucketTrimmed/$encoded';
    }

    final bucketTrimmed = bucket.trim();
    return '$base/storage/v1/object/public/$bucketTrimmed/${Uri.encodeComponent(trimmed)}';
  }

  static String _sanitizeAbsoluteUrl(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      if (value.contains(' ')) return value.replaceAll(' ', '%20');
      return value;
    }

    final normalizedPath = parsed.path
        .split('/')
        .map(_normalizePathSegment)
        .join('/');

    final normalizedQuery = parsed.hasQuery ? _normalizeQuery(parsed.query) : null;

    return parsed
        .replace(
          path: normalizedPath,
          query: normalizedQuery,
        )
        .toString();
  }

  static String _normalizePathSegment(String segment) {
    if (segment.isEmpty) return segment;
    final repairedPercents = segment.replaceAllMapped(
      RegExp(r'%(?![0-9A-Fa-f]{2})'),
      (_) => '%25',
    );
    try {
      return Uri.encodeComponent(Uri.decodeComponent(repairedPercents));
    } catch (_) {
      return Uri.encodeComponent(repairedPercents);
    }
  }

  static String _normalizeQuery(String query) {
    final repairedPercents = query.replaceAllMapped(
      RegExp(r'%(?![0-9A-Fa-f]{2})'),
      (_) => '%25',
    );
    return repairedPercents.replaceAll(' ', '%20');
  }

  static bool same(Track? a, Track b) {
    if (a == null) return false;
    if (a.id != null && b.id != null) return a.id == b.id;
    return a.title == b.title && a.artist == b.artist;
  }
}
