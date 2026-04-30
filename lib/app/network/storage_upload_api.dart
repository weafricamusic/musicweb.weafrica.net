import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/api_env.dart';

class StorageUploadResult {
  const StorageUploadResult({
    required this.bucket,
    required this.path,
    this.publicUrl,
    this.signedUrl,
  });

  final String bucket;
  final String path;
  final String? publicUrl;
  final String? signedUrl;

  factory StorageUploadResult.fromJson(Map<String, dynamic> json) {
    return StorageUploadResult(
      bucket: (json['bucket'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      publicUrl: json['public_url']?.toString(),
      signedUrl: json['signed_url']?.toString(),
    );
  }

  String get bestUrl => (publicUrl?.trim().isNotEmpty ?? false)
      ? publicUrl!.trim()
      : (signedUrl?.trim() ?? '');
}

class StorageUploadApiException implements Exception {
  StorageUploadApiException({
    required this.statusCode,
    required this.bucket,
    required this.message,
    this.responseBody,
  });

  final int statusCode;
  final String bucket;
  final String message;
  final Object? responseBody;

  @override
  String toString() {
    final b = bucket.trim().isEmpty ? '(unknown bucket)' : bucket.trim();
    final body = responseBody == null ? '' : ' body=${responseBody.toString()}';
    return 'Storage upload failed ($statusCode) bucket=$b: $message$body';
  }
}

class StorageUploadApi {
  const StorageUploadApi._();

  static List<String> _bucketRetryOrder(String bucket) {
    final trimmed = bucket.trim();
    if (trimmed.isEmpty) return const [];

    final ordered = <String>[trimmed];

    if (trimmed == 'song-thumbnails') ordered.add('song_thumbnails');
    if (trimmed == 'song_thumbnails') ordered.add('song-thumbnails');

    if (trimmed == 'dj-sets') ordered.add('dj-mixes');
    if (trimmed == 'dj-mixes') ordered.add('dj-sets');

    if (trimmed == 'media') ordered.add('videos');
    if (trimmed == 'videos') ordered.add('media');

    if (trimmed == 'thumbnails') ordered.add('video_thumbnails');
    if (trimmed == 'video_thumbnails') ordered.add('thumbnails');

    final seen = <String>{};
    return ordered.where((b) => seen.add(b)).toList(growable: false);
  }

  static bool _looksLikeBucketNotFound(String message) {
    final m = message.toLowerCase();
    return m.contains('bucket not found') || m.contains('bucket_not_found');
  }

  static Future<StorageUploadResult> upload({
    required String bucket,
    String? prefix,
    required String fileName,
    required Uint8List fileBytes,
    Duration timeout = const Duration(minutes: 30),
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse('${ApiEnv.baseUrl}/api/uploads/storage');

    Future<Response<dynamic>> send({
      required String bucketValue,
      required bool forceRefreshToken,
    }) async {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw StorageUploadApiException(
          statusCode: 401,
          bucket: bucketValue,
          message: 'User not authenticated',
        );
      }

      final bearer = await user.getIdToken(forceRefreshToken);

      final dio = Dio()
        ..options.connectTimeout = timeout
        ..options.receiveTimeout = timeout
        ..options.sendTimeout = timeout;

      final formData = FormData.fromMap({
        'bucket': bucketValue.trim(),
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        if ((prefix ?? '').trim().isNotEmpty) 'prefix': (prefix ?? '').trim(),
      });

      try {
        print(
          '📤 Upload START bucket=$bucketValue file=$fileName bytes=${fileBytes.length}',
        );

        final response = await dio.post<dynamic>(
          uri.toString(),
          data: formData,
          options: Options(
            headers: {
              'Authorization': 'Bearer $bearer',
              'Accept': 'application/json',
            },
            responseType: ResponseType.json,
            validateStatus: (_) => true,
          ),
          onSendProgress: onSendProgress,
          cancelToken: cancelToken,
        );

        print(
          '📥 Upload DONE status=${response.statusCode} data=${response.data}',
        );
        return response;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;

        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          final mins = timeout.inMinutes;
          final secs = timeout.inSeconds;

          throw TimeoutException(
            mins > 0
                ? 'Upload timed out after $mins minutes ($secs s). Try a smaller file or a faster connection.'
                : 'Upload timed out after $secs seconds. Try a smaller file or a faster connection.',
          );
        }

        rethrow;
      }
    }

    final bucketsToTry = _bucketRetryOrder(bucket);
    if (bucketsToTry.isEmpty) {
      throw ArgumentError.value(bucket, 'bucket', 'Bucket cannot be empty.');
    }

    Exception? lastError;

    for (var i = 0; i < bucketsToTry.length; i++) {
      final attemptBucket = bucketsToTry[i];

      Response<dynamic> response = await send(
        bucketValue: attemptBucket,
        forceRefreshToken: false,
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        response = await send(
          bucketValue: attemptBucket,
          forceRefreshToken: true,
        );
      }

      final decoded = response.data;
      final status = response.statusCode ?? 0;

      if (status < 200 || status >= 300) {
        final msg =
            (decoded is Map &&
                (decoded['message'] != null || decoded['error'] != null))
            ? (decoded['message'] ?? decoded['error']).toString()
            : 'Upload failed ($status)';

        final isBucketNotFound = _looksLikeBucketNotFound(msg);
        final hasNextAlias = i < bucketsToTry.length - 1;

        if (isBucketNotFound && hasNextAlias) {
          lastError = StorageUploadApiException(
            statusCode: status,
            bucket: attemptBucket,
            message: msg,
            responseBody: decoded,
          );
          continue;
        }

        throw StorageUploadApiException(
          statusCode: status,
          bucket: attemptBucket,
          message: msg,
          responseBody: decoded,
        );
      }

      if (decoded is! Map) {
        throw Exception('Invalid upload response (expected JSON object).');
      }

      final result = StorageUploadResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (result.bucket.trim().isEmpty || result.path.trim().isEmpty) {
        throw Exception('Upload response missing bucket/path.');
      }

      if (result.bestUrl.isEmpty) {
        throw Exception('Upload response missing public_url/signed_url.');
      }

      return result;
    }

    throw lastError ?? Exception('Upload failed.');
  }
}
