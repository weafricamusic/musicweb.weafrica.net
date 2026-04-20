import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;

import '../../../app/network/storage_upload_api.dart';
import '../models/upload_exception.dart';
import '../models/upload_stage.dart';

/// Cancellation token for upload operations.
///
/// Wraps Dio's token so we can expose a stable API.
class CancelToken {
  CancelToken();
  final dio.CancelToken _dio = dio.CancelToken();

  bool get isCancelled => _dio.isCancelled;
  dio.CancelToken get dioToken => _dio;

  void cancel([String? reason]) {
    if (_dio.isCancelled) return;
    _dio.cancel(reason ?? 'cancelled');
  }
}

class StorageUploadResult {
  const StorageUploadResult({
    required this.path,
    required this.publicUrl,
  });

  final String path;
  final String publicUrl;
}

class UploadStorage {
  const UploadStorage();

  UploadException _mapError(Object e) {
    if (e is TimeoutException) {
      return UploadException(
        userMessage: 'WEAFRICA: Upload timed out. Try a smaller file or better network.',
        technicalMessage: e.message ?? e.toString(),
        canRetry: true,
        stage: UploadStage.uploading,
        originalError: e,
      );
    }

    if (e is StorageUploadApiException) {
      final status = e.statusCode;
      final msgLower = e.message.toLowerCase();

      String userMessage = 'WEAFRICA: Upload failed. Please try again.';

      if (status == 401) {
        userMessage = 'WEAFRICA: Session expired. Please sign in again and retry.';
      } else if (status == 403 || msgLower.contains('row-level security') || msgLower.contains('permission denied')) {
        userMessage = 'WEAFRICA: Upload blocked by permissions (403). Please re-login or contact support.';
      } else if (status == 413 || msgLower.contains('payload too large') || msgLower.contains('request entity too large')) {
        userMessage = 'WEAFRICA: File is too large to upload. Try a smaller file.';
      } else if (status >= 500) {
        userMessage = 'WEAFRICA: Server error during upload. Please try again shortly.';
      } else if (status == 400) {
        userMessage = 'WEAFRICA: Upload request rejected (400). Please try a different file.';
      }

      return UploadException(
        userMessage: userMessage,
        technicalMessage: e.toString(),
        canRetry: true,
        stage: UploadStage.uploading,
        originalError: e,
      );
    }

    final msg = e.toString();
    if (msg.toLowerCase().contains('no bytes available')) {
      return UploadException(
        userMessage: 'WEAFRICA: File picker did not provide bytes. Please re-select the file and try again.',
        technicalMessage: msg,
        canRetry: true,
        stage: UploadStage.preparing,
        originalError: e,
      );
    }

    return UploadException(
      userMessage: 'WEAFRICA: Upload failed. Please try again.',
      technicalMessage: msg,
      canRetry: true,
      stage: UploadStage.uploading,
      originalError: e,
    );
  }

  Future<StorageUploadResult> uploadWithRetry({
    required String bucket,
    required String prefix,
    required String fileName,
    required Uint8List bytes,
    required Duration timeout,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final result = await StorageUploadApi.upload(
          bucket: bucket,
          prefix: prefix,
          fileName: fileName,
          fileBytes: bytes,
          timeout: timeout,
          cancelToken: cancelToken?.dioToken,
          onSendProgress: onProgress,
        );

        return StorageUploadResult(path: result.path, publicUrl: result.bestUrl);
      } catch (e) {
        lastError = e;
        if (cancelToken?.isCancelled ?? false) {
          throw const UploadException(
            userMessage: 'Upload cancelled',
            technicalMessage: 'Cancelled by user',
            canRetry: true,
            stage: UploadStage.cancelled,
          );
        }

        final isLast = attempt >= maxAttempts;
        if (isLast) {
          throw _mapError(e);
        }

        final delay = Duration(seconds: 1 << (attempt - 1));
        developer.log('Upload retry attempt=$attempt delay=${delay.inSeconds}s err=$e', name: 'WEAFRICA.UploadStorage');
        await Future<void>.delayed(delay);
      }
    }

    throw UploadException(
      userMessage: 'WEAFRICA: Upload failed. Please try again.',
      technicalMessage: lastError?.toString() ?? 'unknown',
      canRetry: true,
      stage: UploadStage.uploading,
      originalError: lastError,
    );
  }
}
