import 'package:flutter/foundation.dart';

import '../../app/config/supabase_env.dart';
import '../../app/media/artwork_resolver.dart';

class Song {
  static const String bucketName = 'song-thumbnails';
  static const String audioBucketName = 'songs';

  final String id;
  final String title;
  final String artist;
  final String? thumbnail;
  final String? audioUrl;

  final Duration duration;
  final bool isPlaying;
  final bool isTrending;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    this.audioUrl,
    required this.duration,
    this.isPlaying = false,
    this.isTrending = false,
  });

  Song copyWith({
    bool? isPlaying,
    bool? isTrending,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      thumbnail: thumbnail,
      audioUrl: audioUrl,
      duration: duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isTrending: isTrending ?? this.isTrending,
    );
  }

  /// Alias for consistency with existing widgets.
  ///
  /// `thumbnail` can be:
  /// - a storage object path (e.g. `user_folder/file.jpg`)
  /// - a full URL
  String? get imagePath => thumbnail;

  /// Best-effort public URL for rendering artwork.
  ///
  /// Note: `SmartImage` still tries multiple buckets as a fallback.
  String? get imageUrl {
    if (!kDebugMode) return _resolvePublicUrl(imagePath, bucket: bucketName);
    debugPrint('🖼️ Getting image URL for thumbnail: $thumbnail');
    debugPrint('   imagePath: $imagePath');
    debugPrint('   bucketName: $bucketName');
    final url = _resolvePublicUrl(imagePath, bucket: bucketName);
    debugPrint(url == null ? '❌ Thumbnail is null/empty' : '✅ Generated URL: $url');
    return url;
  }

  String? get fullAudioUrl {
    if (!kDebugMode) return _resolvePublicUrl(audioUrl, bucket: audioBucketName);
    debugPrint('🔊 Getting audio URL for audioUrl: $audioUrl');
    final url = _resolvePublicUrl(audioUrl, bucket: audioBucketName);
    debugPrint(url == null ? '❌ Audio URL is null/empty' : '✅ Generated URL: $url');
    return url;
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      debugPrint('🎵 Creating Song from JSON');
      debugPrint('   JSON keys: ${json.keys}');
    }

    final artists = json['artists'];
    String artistName = (json['artist'] ?? '').toString();

    if (artistName.trim().isEmpty) {
      if (artists is Map) {
        artistName = (artists['name'] ?? '').toString();
      } else if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map) {
          artistName = (first['name'] ?? '').toString();
        }
      }
    }

    if (artistName.trim().isEmpty) {
      artistName = 'Unknown Artist';
    }

    final durationRaw = json['duration'] ?? json['duration_seconds'] ?? json['durationSeconds'];
    final seconds = durationRaw is num ? durationRaw.toInt() : int.tryParse(durationRaw?.toString() ?? '');

    String? pickThumbnail() {
      if (kDebugMode) {
        debugPrint('🎨 Looking for thumbnail in JSON');
      }
      final value = pickArtworkValue(
        json,
        keys: const [
          'artwork_url',      // ✅ First priority - where your images are stored
          'artworkUrl',
          'thumbnail_url',
          'thumbnailUrl',
          'thumbnail',
          'image_url',
          'imageUrl',
        ],
      );
      if (kDebugMode) {
        if (value != null) {
          debugPrint('✅ Found thumbnail: $value');
        } else {
          debugPrint('❌ No thumbnail found in any key');
        }
      }
      return value;
    }

    final song = Song(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? 'Unknown Title').toString(),
      artist: artistName,
      thumbnail: pickThumbnail(),
      audioUrl: (json['audio_url'] ?? json['audioUrl'] ?? json['url'])?.toString(),
      duration: Duration(seconds: seconds ?? 180),
      isPlaying: false,
      isTrending: false,
    );

    if (kDebugMode) {
      debugPrint('✅ Created Song: ${song.title}');
      debugPrint('   thumbnail: ${song.thumbnail}');
      debugPrint('   imageUrl: ${song.imageUrl}');
      debugPrint('   audioUrl: ${song.audioUrl}');
    }

    return song;
  }

  static String? _resolvePublicUrl(String? raw, {required String bucket}) {
    if (raw == null) return null;
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Handle encoded placeholders seen in some rows.
    trimmed = trimmed.replaceAll('%3CSUPABASE_URL%3E', '<SUPABASE_URL>');

    // Strip leading slash.
    while (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }

    final base = SupabaseEnv.supabaseUrl.trim();

    // Replace placeholder if present.
    if (trimmed.contains('<SUPABASE_URL>') && base.isNotEmpty) {
      trimmed = trimmed.replaceAll('<SUPABASE_URL>', base);
    }

    // Full URL already.
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      trimmed = _sanitizeAbsoluteUrl(trimmed);

      // Normalize common Supabase storage URL variant missing `/public/`.
      // Example seen in data: /storage/v1/object/songs/<path>
      // This will only work if the bucket is public; otherwise you must use signed URLs.
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

    // Already a storage path.
    if (trimmed.startsWith('storage/v1/object/public/')) {
      return '$base/$trimmed';
    }

    // FIX: Check if the path already includes a known bucket
    final knownBuckets = [
      'album-covers',
      'song-thumbnails', 
      'song_thumbnails',
      'songs', 
      'media', 
      'videos', 
      'video_thumbnails',
      'uploads'
    ];
    
    // Helper function to check if path starts with known bucket
    bool startsWithKnownBucket() {
      for (final knownBucket in knownBuckets) {
        if (trimmed.startsWith('$knownBucket/')) {
          return true;
        }
      }
      return false;
    }

    // If path already includes a bucket, use it directly
    if (startsWithKnownBucket()) {
      // Path already has bucket prefix - use the full path
      if (trimmed.startsWith('song_thumbnails/')) {
        trimmed = trimmed.replaceFirst('song_thumbnails/', 'song-thumbnails/');
      }

      final encoded = trimmed
          .split('/')
          .map((segment) => Uri.encodeComponent(segment))
          .join('/');
      final url = '$base/storage/v1/object/public/$encoded';
      if (kDebugMode) {
        debugPrint('   📦 Using known bucket path: $url');
      }
      return url;
    }

    // If path contains slashes but doesn't start with known bucket,
    // assume it's a path within the provided bucket
    if (trimmed.contains('/')) {
      final encoded = trimmed
          .split('/')
          .map((segment) => Uri.encodeComponent(segment))
          .join('/');
      final url = '$base/storage/v1/object/public/$bucket/$encoded';
      if (kDebugMode) {
        debugPrint('   📦 Using provided bucket: $url');
      }
      return url;
    }

    // Plain filename: assume bucket.
    if (bucket == 'song_thumbnails' || bucket == 'song-thumbnails') {
      final url = '$base/storage/v1/object/public/song-thumbnails/${Uri.encodeComponent(trimmed)}';
      if (kDebugMode) {
        debugPrint('   📦 Plain filename in thumbnails bucket: $url');
      }
      return url;
    }
    
    final url = '$base/storage/v1/object/public/$bucket/${Uri.encodeComponent(trimmed)}';
    if (kDebugMode) {
      debugPrint('   📦 Default path: $url');
    }
    return url;
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
}