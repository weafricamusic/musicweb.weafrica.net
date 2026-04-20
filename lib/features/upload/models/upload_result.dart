// WEAFRICA Music — Upload Result

import 'media_type.dart';
import 'upload_exception.dart';

class UploadResult {
  const UploadResult({
    required this.success,
    required this.uploadId,
    this.draftId,
    this.primaryUrl,
    this.secondaryUrl,
    this.error,
    this.mediaType,
    this.duration,
  });

  final bool success;
  final String uploadId;
  final String? draftId;
  final String? primaryUrl;
  final String? secondaryUrl;
  final UploadException? error;
  final MediaType? mediaType;
  final Duration? duration;

  Map<String, dynamic> toJson() => {
        'success': success,
        'uploadId': uploadId,
        'draftId': draftId,
        'primaryUrl': primaryUrl,
        'secondaryUrl': secondaryUrl,
        if (error != null) 'error': error!.toJson(),
        if (mediaType != null) 'mediaType': mediaType!.name,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
      };
}
