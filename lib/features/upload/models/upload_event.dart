// WEAFRICA Music — Upload Event

import 'upload_exception.dart';
import 'upload_stage.dart';

class UploadEvent {
  const UploadEvent({
    required this.uploadId,
    required this.stage,
    required this.message,
    this.progress,
    this.primaryProgress,
    this.secondaryProgress,
    this.draftId,
    this.error,
  });

  final String uploadId;
  final UploadStage stage;
  final double? progress;
  final double? primaryProgress;
  final double? secondaryProgress;
  final String message;
  final String? draftId;
  final UploadException? error;

  bool get hasProgress => progress != null;
  bool get isCompleted => stage == UploadStage.completed;
  bool get isFailed => stage == UploadStage.failed;
  bool get isCancelled => stage == UploadStage.cancelled;

  UploadEvent copyWith({
    String? uploadId,
    UploadStage? stage,
    double? progress,
    double? primaryProgress,
    double? secondaryProgress,
    String? message,
    String? draftId,
    UploadException? error,
  }) {
    return UploadEvent(
      uploadId: uploadId ?? this.uploadId,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      primaryProgress: primaryProgress ?? this.primaryProgress,
      secondaryProgress: secondaryProgress ?? this.secondaryProgress,
      message: message ?? this.message,
      draftId: draftId ?? this.draftId,
      error: error ?? this.error,
    );
  }
}
