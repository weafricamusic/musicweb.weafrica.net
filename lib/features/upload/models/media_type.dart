// WEAFRICA Music — Media Type Enum

enum MediaType {
  song,
  video;

  String get bucketName => this == MediaType.song ? 'songs' : 'videos';

  String get thumbnailBucket => this == MediaType.song ? 'song-thumbnails' : 'video_thumbnails';

  String get extension => this == MediaType.song ? 'm4a' : 'mp4';

  String get displayName => this == MediaType.song ? 'Song' : 'Video';

  /// Conservative defaults; can be revisited once backend limit are finalized.
  int get maxSizeBytes => this == MediaType.song
      ? 200 * 1024 * 1024 // 200MB
      : 500 * 1024 * 1024; // 500MB
}
