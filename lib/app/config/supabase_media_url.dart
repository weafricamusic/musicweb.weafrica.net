import 'package:flutter/foundation.dart';

import 'supabase_env.dart';

/// Utilities for turning Supabase Storage object paths into usable HTTPS URLs.
///
/// Supported inputs:
/// - Full URLs: https://... (returned as-is)
/// - Storage shorthand: `bucket/path/to/file.ext`
/// - Explicit scheme: `storage://bucket/path/to/file.ext`
class SupabaseMediaUrl {
  const SupabaseMediaUrl._();

  static String _normalizeBucket(String bucket) {
    final b = bucket.trim();
    if (b == 'song_thumbnails') return 'song-thumbnails';
    return b;
  }

  static Uri _normalizeAbsolute(Uri uri) {
    // Normalize legacy bucket aliases even when the URL is already absolute.
    // This is critical because some rows store full HTTPS URLs that point at
    // `song_thumbnails` (underscore) while the real bucket is `song-thumbnails`.
    final p = uri.path;
    final normalizedPath = p
        .replaceAll(
          '/storage/v1/object/public/song_thumbnails/',
          '/storage/v1/object/public/song-thumbnails/',
        )
        .replaceAll(
          '/storage/v1/object/song_thumbnails/',
          '/storage/v1/object/song-thumbnails/',
        )
        .replaceAll(
          '/storage/v1/object/sign/song_thumbnails/',
          '/storage/v1/object/sign/song-thumbnails/',
        );

    if (normalizedPath == p) return uri;
    return uri.replace(path: normalizedPath);
  }

  static Uri? normalize(Uri? uri) {
    if (uri == null) return null;

    // Already absolute.
    if (uri.hasScheme && uri.scheme != 'storage') {
      return _normalizeAbsolute(uri);
    }

    final supabaseBase = SupabaseEnv.supabaseUrl;
    if (supabaseBase.isEmpty) return uri;

    String? bucket;
    String? objectPath;

    if (uri.scheme == 'storage') {
      bucket = uri.host.trim().isEmpty ? null : uri.host;
      objectPath = uri.path.replaceFirst(RegExp(r'^/+'), '');
    } else {
      // No scheme: expect `bucket/path...`
      final segs = uri.pathSegments;
      if (segs.length >= 2) {
        bucket = segs.first;
        objectPath = segs.skip(1).join('/');
      }
    }

    if (bucket == null || objectPath == null || objectPath.isEmpty) {
      return uri;
    }

    bucket = _normalizeBucket(bucket);

    final base = Uri.parse(supabaseBase);
    final resolved = base.replace(
      path: '/storage/v1/object/public/$bucket/$objectPath',
      query: null,
      fragment: null,
    );

    if (kDebugMode) {
      debugPrint('SupabaseMediaUrl.normalize: $uri -> $resolved');
    }

    return resolved;
  }
}
