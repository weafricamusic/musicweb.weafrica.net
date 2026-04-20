import '../models/media_type.dart';

/// Lightweight UI model for showing upload queue/persistence in the Studio.
class UploadQueueItem {
  const UploadQueueItem({
    required this.uploadId,
    required this.mediaType,
    required this.stage,
    required this.message,
    required this.progress,
    required this.updatedAtUtcMs,
    this.canRetry,
  });

  final String uploadId;
  final MediaType mediaType;
  final String stage;
  final String message;
  final double progress;
  final int updatedAtUtcMs;
  final bool? canRetry;
}
