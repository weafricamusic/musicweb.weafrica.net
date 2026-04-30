class BeatModel {
  final String id;
  final String name;
  final String genre;
  final int duration;
  final String? audioUrl;
  final String? storageBucket;
  final String? storagePath;
  final int bpm;
  final String? coverImage;

  BeatModel({
    required this.id,
    required this.name,
    required this.genre,
    required this.duration,
    this.audioUrl,
    this.storageBucket,
    this.storagePath,
    required this.bpm,
    this.coverImage,
  });

  factory BeatModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawAudioUrl = json['audio_url'];
    final dynamic rawStoragePath = json['storage_path'];

    final String? audioUrl = rawAudioUrl?.toString();
    final String? storagePath = rawStoragePath?.toString();

    return BeatModel(
      id: json['id'].toString(),
      name: json['name'] ?? 'Untitled Beat',
      genre: json['genre'] ?? 'Afrobeat',
      duration: json['duration_seconds'] ?? json['duration'] ?? 30,
      audioUrl: audioUrl,
      storageBucket: json['storage_bucket']?.toString(),
      storagePath: storagePath,
      bpm: json['bpm'] ?? 120,
      coverImage: json['cover_image'],
    );
  }

  bool get hasPlayableUrl =>
      (audioUrl != null && audioUrl!.trim().isNotEmpty) ||
      (storagePath != null && storagePath!.trim().isNotEmpty);

  static ({String bucket, String path})? _extractBucketAndPathFromStorageUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return null;

    final segments = parsed.pathSegments;
    if (segments.isEmpty) return null;

    final objectIndex = segments.indexOf('object');
    if (objectIndex == -1 || objectIndex + 2 >= segments.length) return null;

    final mode = segments[objectIndex + 1];
    if (mode != 'public' && mode != 'sign' && mode != 'authenticated') return null;

    final bucket = segments[objectIndex + 2].trim();
    if (bucket.isEmpty) return null;

    final pathSegments = segments.sublist(objectIndex + 3);
    if (pathSegments.isEmpty) return null;

    final objectPath = pathSegments.join('/').trim();
    if (objectPath.isEmpty) return null;

    return (bucket: bucket, path: objectPath);
  }

  Future<String?> resolveAudioUrl(
    dynamic supabaseClient, {
    int expiresInSeconds = 60 * 60,
    String defaultBucket = 'ai_beats',
  }) async {
    Future<String?> signFromStoragePath({
      required String rawPath,
      required String bucket,
    }) async {
      final normalizedPath = rawPath.trim();
      if (normalizedPath.isEmpty) return null;

      final signed = await supabaseClient.storage
          .from(bucket)
          .createSignedUrl(normalizedPath, expiresInSeconds);
      if (signed.error != null) return null;
      return signed.data?.signedUrl;
    }

    // Prefer storage path whenever available so we always generate a fresh
    // signed URL instead of relying on potentially stale `audio_url` values.
    final rawStoragePath = storagePath?.trim();
    if (rawStoragePath != null && rawStoragePath.isNotEmpty) {
      if (rawStoragePath.startsWith('http://') || rawStoragePath.startsWith('https://')) {
        final extracted = _extractBucketAndPathFromStorageUrl(rawStoragePath);
        if (extracted != null) {
          final resolved = await signFromStoragePath(
            rawPath: extracted.path,
            bucket: extracted.bucket,
          );
          if (resolved != null && resolved.isNotEmpty) return resolved;
        }

        // If parsing fails, return as-is for back-compat.
        return rawStoragePath;
      }

      final bucket = (storageBucket?.trim().isNotEmpty ?? false)
          ? storageBucket!.trim()
          : defaultBucket;
      final resolved = await signFromStoragePath(rawPath: rawStoragePath, bucket: bucket);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }

    final direct = audioUrl?.trim();
    if (direct == null || direct.isEmpty) return null;

    // If `audio_url` looks like a storage endpoint URL, re-sign it to avoid
    // 404s/expiry problems from old signed links.
    if (direct.startsWith('http://') || direct.startsWith('https://')) {
      final extracted = _extractBucketAndPathFromStorageUrl(direct);
      if (extracted != null) {
        final resolved = await signFromStoragePath(
          rawPath: extracted.path,
          bucket: extracted.bucket,
        );
        if (resolved != null && resolved.isNotEmpty) return resolved;
      }
    }

    return direct;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'genre': genre,
      'duration_seconds': duration,
      'audio_url': audioUrl,
      'storage_bucket': storageBucket,
      'storage_path': storagePath,
      'bpm': bpm,
      'cover_image': coverImage,
    };
  }
}
