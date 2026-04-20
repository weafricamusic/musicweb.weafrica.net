// WEAFRICA Music — Upload Exception

import 'upload_stage.dart';

class UploadException implements Exception {
  const UploadException({
    required this.userMessage,
    required this.technicalMessage,
    required this.stage,
    this.canRetry = true,
    this.originalError,
  });

  final String userMessage;
  final String technicalMessage;
  final bool canRetry;
  final UploadStage stage;
  final Object? originalError;

  Map<String, dynamic> toJson() => {
        'userMessage': userMessage,
        'technicalMessage': technicalMessage,
        'canRetry': canRetry,
        'stage': stage.name,
      };

  @override
  String toString() => userMessage;
}

