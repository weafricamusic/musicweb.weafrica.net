import 'media_type.dart';
import 'upload_exception.dart';
import 'upload_stage.dart';

class UploadStatus {
  const UploadStatus({
    required this.uploadId,
    required this.mediaType,
    required this.stage,
    required this.message,
    required this.overallProgress,
    required this.primaryProgress,
    required this.secondaryProgress,
    this.draftId,
    this.error,
    required this.updatedAtUtcMs,
  });

  final String uploadId;
  final MediaType mediaType;
  final UploadStage stage;
  final String message;

  /// Weighted overall progress in [0,1].
  final double? overallProgress;

  /// Primary file progress (audio/video) in [0,1].
  final double? primaryProgress;

  /// Secondary file progress (artwork/thumb) in [0,1].
  final double? secondaryProgress;

  final String? draftId;
  final UploadException? error;

  final int updatedAtUtcMs;

  Map<String, dynamic> toJson() => {
        'upload_id': uploadId,
        'media_type': mediaType.name,
        'stage': stage.name,
        'message': message,
        'overall_progress': overallProgress,
        'primary_progress': primaryProgress,
        'secondary_progress': secondaryProgress,
        'draft_id': draftId,
        'updated_at_utc_ms': updatedAtUtcMs,
        if (error != null)
          'error': {
            'user_message': error!.userMessage,
            'technical_message': error!.technicalMessage,
            'can_retry': error!.canRetry,
            'stage': error!.stage.name,
          },
      };

  static UploadStatus? tryFromJson(Map<String, dynamic> json) {
    try {
      final uploadId = (json['upload_id'] ?? '').toString().trim();
      if (uploadId.isEmpty) return null;

      final mediaTypeRaw = (json['media_type'] ?? '').toString();
      final mediaType = MediaType.values.firstWhere(
        (e) => e.name == mediaTypeRaw,
        orElse: () => MediaType.song,
      );

      final stageRaw = (json['stage'] ?? '').toString();
      final stage = UploadStage.values.firstWhere(
        (e) => e.name == stageRaw,
        orElse: () => UploadStage.preparing,
      );

      UploadException? error;
      final errorJson = json['error'];
      if (errorJson is Map) {
        final stage2Raw = (errorJson['stage'] ?? '').toString();
        final stage2 = UploadStage.values.firstWhere(
          (e) => e.name == stage2Raw,
          orElse: () => stage,
        );
        error = UploadException(
          userMessage: (errorJson['user_message'] ?? '').toString(),
          technicalMessage: (errorJson['technical_message'] ?? '').toString(),
          canRetry: (errorJson['can_retry'] as bool?) ?? true,
          stage: stage2,
        );
      }

      double? d(dynamic v) => v is num ? v.toDouble() : null;

      return UploadStatus(
        uploadId: uploadId,
        mediaType: mediaType,
        stage: stage,
        message: (json['message'] ?? '').toString(),
        overallProgress: d(json['overall_progress']),
        primaryProgress: d(json['primary_progress']),
        secondaryProgress: d(json['secondary_progress']),
        draftId: (json['draft_id'] ?? '').toString().trim().isEmpty ? null : (json['draft_id'] ?? '').toString(),
        error: error,
        updatedAtUtcMs: (json['updated_at_utc_ms'] as int?) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
