import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/config/api_env.dart';
import '../../../app/media/upload_media_compressor.dart' show UploadCompressionPreset;
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/utils/platform_bytes_reader.dart';
import '../models/media_type.dart';
import '../models/upload_event.dart';
import '../models/upload_exception.dart';
import '../models/upload_result.dart';
import '../models/upload_stage.dart';
import '../models/upload_status.dart';
import '../../../services/journey_service.dart';
import 'upload_compressor.dart';
import 'upload_persistence.dart';
import 'upload_queue.dart';
import 'upload_storage.dart';

/// Core upload state machine.
///
/// Responsibilities:
/// - Stage transitions + consistent events
/// - Retry for draft create/finalize + storage retries
/// - Cancellation via [cancelUpload]
/// - Queueing via [UploadQueue]
/// - Progress persistence via [UploadPersistence]
class UploadStateMachine {
  UploadStateMachine({
    SupabaseClient? supabaseClient,
    UploadQueue? queue,
    UploadPersistence? persistence,
    UploadStorage? storage,
    UploadCompressor? compressor,
  })  : _client = supabaseClient ?? Supabase.instance.client,
        _queue = queue ?? UploadQueue.instance,
        _persistence = persistence ?? UploadPersistence.instance,
        _storage = storage ?? const UploadStorage(),
        _compressor = compressor ?? const UploadCompressor();

  static final UploadStateMachine instance = UploadStateMachine();

  final SupabaseClient _client;
  final UploadQueue _queue;
  final UploadPersistence _persistence;
  final UploadStorage _storage;
  final UploadCompressor _compressor;

  final _events = StreamController<UploadEvent>.broadcast();
  Stream<UploadEvent> get events => _events.stream;

  final Map<String, CancelToken> _active = <String, CancelToken>{};
  final Map<String, int> _lastPersistAtMs = <String, int>{};

  String _generateUploadId() {
    final now = DateTime.now().toUtc();
    return 'upload_${now.millisecondsSinceEpoch}_${now.microsecond}';
  }

  bool cancelUpload(String uploadId) {
    final active = _active[uploadId];
    if (active != null) {
      active.cancel('User cancelled');
      return true;
    }
    return _queue.cancelQueued(uploadId);
  }

  Future<List<UploadStatus>> loadPendingUploads() => _persistence.loadAll();

  double _weightedOverall({required bool hasSecondary, required double primary, required double secondary}) {
    if (!hasSecondary) return primary.clamp(0, 1);
    return (0.9 * primary + 0.1 * secondary).clamp(0, 1);
  }

  Future<void> _persistThrottled(UploadStatus status) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final last = _lastPersistAtMs[status.uploadId] ?? 0;
    if (status.stage == UploadStage.uploading && now - last < 400) return;
    _lastPersistAtMs[status.uploadId] = now;
    await _persistence.upsert(status);
  }

  void _emit({
    required String uploadId,
    required MediaType mediaType,
    required UploadStage stage,
    required String message,
    required bool hasSecondary,
    required double primary,
    required double secondary,
    String? draftId,
    UploadException? error,
  }) {
    final overall = _weightedOverall(hasSecondary: hasSecondary, primary: primary, secondary: secondary);

    final status = UploadStatus(
      uploadId: uploadId,
      mediaType: mediaType,
      stage: stage,
      message: message,
      overallProgress: overall,
      primaryProgress: primary,
      secondaryProgress: secondary,
      draftId: draftId,
      error: error,
      updatedAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    _events.add(
      UploadEvent(
        uploadId: uploadId,
        stage: stage,
        message: message,
        progress: overall,
        primaryProgress: primary,
        secondaryProgress: secondary,
        draftId: draftId,
        error: error,
      ),
    );

    unawaited(_persistThrottled(status));
  }

  void _throwIfCancelled(CancelToken token, UploadStage stage) {
    if (!token.isCancelled) return;
    throw UploadException(
      userMessage: 'Upload cancelled',
      technicalMessage: 'Cancelled at stage ${stage.name}',
      canRetry: true,
      stage: UploadStage.cancelled,
    );
  }

  Future<T> _retry<T>(
    Future<T> Function() op, {
    required int maxAttempts,
    required bool Function(Object e) shouldRetry,
  }) async {
    Object? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await op();
      } catch (e) {
        last = e;
        if (attempt >= maxAttempts || !shouldRetry(e)) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    throw last ?? Exception('retry failed');
  }

  bool _isTransient(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('timed out')) return true;
    if (msg.contains('timeout')) return true;
    if (msg.contains('socket')) return true;
    if (msg.contains('connection')) return true;
    if (msg.contains('network')) return true;
    return false;
  }

  String _safeFilename(String? name, {required String fallbackExt}) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'file.$fallbackExt';
    return n.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  String _stripExtension(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.replaceAll(RegExp(r'\.[^./\\]+$'), '');
  }

  String _forcedTargetName({required String originalName, required String forcedExt}) {
    final base = _stripExtension(originalName);
    final raw = base.isEmpty ? 'file.$forcedExt' : '$base.$forcedExt';
    return _safeFilename(raw, fallbackExt: forcedExt);
  }

  Future<UploadResult> uploadSong({
    required String title,
    required String artist,
    required String genre,
    required String country,
    required String language,
    required PlatformFile audioFile,
    PlatformFile? artworkFile,
    String? albumId,
    String? reuseDraftId,
    UploadCompressionPreset compressionPreset = UploadCompressionPreset.balanced,
    void Function(UploadEvent event)? onEvent,
  }) {
    final uploadId = _generateUploadId();
    return _queue.enqueue<UploadResult>(
      id: uploadId,
      name: 'Song: ${title.trim().isEmpty ? audioFile.name : title}',
      task: () => _runUpload(
        uploadId: uploadId,
        type: MediaType.song,
        title: title,
        caption: null,
        artist: artist,
        genre: genre,
        country: country,
        language: language,
        category: null,
        mediaFile: audioFile,
        imageFile: artworkFile,
        albumId: albumId,
        reuseDraftId: reuseDraftId,
        compressionPreset: compressionPreset,
        onEvent: onEvent,
      ),
    );
  }

  Future<UploadResult> uploadVideo({
    required String title,
    required PlatformFile videoFile,
    PlatformFile? thumbnailFile,
    String? reuseDraftId,
    String? category,
    UploadCompressionPreset compressionPreset = UploadCompressionPreset.balanced,
    void Function(UploadEvent event)? onEvent,
  }) {
    final uploadId = _generateUploadId();
    return _queue.enqueue<UploadResult>(
      id: uploadId,
      name: 'Video: ${title.trim().isEmpty ? videoFile.name : title}',
      task: () => _runUpload(
        uploadId: uploadId,
        type: MediaType.video,
        title: title,
        caption: title,
        artist: null,
        genre: null,
        country: null,
        language: null,
        category: category,
        mediaFile: videoFile,
        imageFile: thumbnailFile,
        albumId: null,
        reuseDraftId: reuseDraftId,
        compressionPreset: compressionPreset,
        onEvent: onEvent,
      ),
    );
  }

  Future<UploadResult> _runUpload({
    required String uploadId,
    required MediaType type,
    required String title,
    required String? caption,
    required String? artist,
    required String? genre,
    required String? country,
    required String? language,
    required String? category,
    required PlatformFile mediaFile,
    required PlatformFile? imageFile,
    required String? albumId,
    required String? reuseDraftId,
    required UploadCompressionPreset compressionPreset,
    required void Function(UploadEvent event)? onEvent,
  }) async {
    final started = DateTime.now();
    final cancel = CancelToken();
    _active[uploadId] = cancel;

    double primary = 0;
    double secondary = 0;
    final hasSecondary = imageFile != null;

    void emit(UploadStage stage, {String? message, String? draftId, UploadException? error}) {
      final m = message ?? stage.defaultMessage;
      final overall = _weightedOverall(hasSecondary: hasSecondary, primary: primary, secondary: secondary);

      _emit(
        uploadId: uploadId,
        mediaType: type,
        stage: stage,
        message: m,
        hasSecondary: hasSecondary,
        primary: primary,
        secondary: secondary,
        draftId: draftId,
        error: error,
      );
      onEvent?.call(
        UploadEvent(
          uploadId: uploadId,
          stage: stage,
          message: m,
          progress: overall,
          primaryProgress: primary,
          secondaryProgress: secondary,
          draftId: draftId,
          error: error,
        ),
      );
    }

    try {
      emit(UploadStage.preparing, message: 'Preparing upload…');

      final user = FirebaseAuth.instance.currentUser;
      final uid = (user?.uid ?? '').trim();
      if (uid.isEmpty) {
        throw const UploadException(
          userMessage: 'WEAFRICA: Please sign in to upload.',
          technicalMessage: 'FirebaseAuth.currentUser missing',
          canRetry: false,
          stage: UploadStage.preparing,
        );
      }

      if (mediaFile.size > 0 && mediaFile.size > type.maxSizeBytes) {
        throw UploadException(
          userMessage: 'WEAFRICA: ${type.displayName} file is too large.',
          technicalMessage: 'size=${mediaFile.size} max=${type.maxSizeBytes}',
          canRetry: false,
          stage: UploadStage.preparing,
        );
      }

      _throwIfCancelled(cancel, UploadStage.preparing);

      final now = DateTime.now().toUtc();
      final ts = now.millisecondsSinceEpoch;

      final mediaName = _forcedTargetName(originalName: mediaFile.name, forcedExt: type.extension);
      final imageName = imageFile == null ? null : _forcedTargetName(originalName: imageFile.name, forcedExt: 'jpg');

      final mediaBucket = type.bucketName;
      final imageBucket = type.thumbnailBucket;

      final mediaPrefix = type == MediaType.song ? 'uploads/$uid/$ts' : 'videos/$uid/$ts';
      final imagePrefix = mediaPrefix;

      final mediaPath = '$mediaPrefix/$mediaName';
      final imagePath = imageName == null ? null : '$imagePrefix/$imageName';

      final mediaUrlPlanned = _client.storage.from(mediaBucket).getPublicUrl(mediaPath);
      final imageUrlPlanned = imagePath == null ? null : _client.storage.from(imageBucket).getPublicUrl(imagePath);

      emit(UploadStage.creatingDraft);

      String? draftId = reuseDraftId;
      if (draftId == null || draftId.trim().isEmpty) {
        draftId = await _retry<String?>(
          () async {
            _throwIfCancelled(cancel, UploadStage.creatingDraft);
            return _createDraft(
              type: type,
              title: title,
              caption: caption,
              artist: artist,
              genre: genre,
              country: country,
              language: language,
              category: category,
              albumId: albumId,
              mediaUrlPlanned: mediaUrlPlanned,
              mediaBucket: mediaBucket,
              mediaPath: mediaPath,
              filePath: mediaPath,
              imageUrlPlanned: imageUrlPlanned,
              imageBucket: imageBucket,
              imagePath: imagePath,
            );
          },
          maxAttempts: 3,
          shouldRetry: (e) => _isTransient(e),
        );
      }

      if (draftId == null || draftId.trim().isEmpty) {
        throw const UploadException(
          userMessage: 'WEAFRICA: Could not create draft. Please try again.',
          technicalMessage: 'draft id missing',
          canRetry: true,
          stage: UploadStage.creatingDraft,
        );
      }

      final nonNullDraftId = draftId;

      emit(
        UploadStage.compressing,
        draftId: nonNullDraftId,
        message: 'Optimizing (${compressionPreset.label})…',
      );

      _throwIfCancelled(cancel, UploadStage.compressing);
      final mediaBytes = await readPlatformFileBytes(mediaFile);
      _throwIfCancelled(cancel, UploadStage.compressing);
      final imageBytes = imageFile == null ? null : await readPlatformFileBytes(imageFile);

      final compressedPrimary = await _compressor.compressPrimary(
        type: type,
        bytes: mediaBytes,
        originalName: mediaFile.name,
        preset: compressionPreset,
      );

      final compressedImage = (imageFile != null && imageBytes != null)
          ? await _compressor.compressImage(
              bytes: imageBytes,
              originalName: imageFile.name,
            )
          : null;

      emit(UploadStage.uploading, draftId: nonNullDraftId);

      Future<StorageUploadResult> uploadPrimary() {
        return _storage.uploadWithRetry(
          bucket: mediaBucket,
          prefix: mediaPrefix,
          fileName: mediaName,
          bytes: compressedPrimary.bytes,
          timeout: type == MediaType.song ? const Duration(minutes: 30) : const Duration(minutes: 60),
          cancelToken: cancel,
          onProgress: (sent, total) {
            if (total <= 0) return;
            primary = (sent / total).clamp(0, 1);
            emit(UploadStage.uploading, draftId: nonNullDraftId);
          },
        );
      }

      Future<StorageUploadResult?> uploadSecondary() async {
        if (compressedImage == null || imageName == null) return null;
        return _storage.uploadWithRetry(
          bucket: imageBucket,
          prefix: imagePrefix,
          fileName: imageName,
          bytes: compressedImage.bytes,
          timeout: const Duration(minutes: 10),
          cancelToken: cancel,
          onProgress: (sent, total) {
            if (total <= 0) return;
            secondary = (sent / total).clamp(0, 1);
            emit(UploadStage.uploading, draftId: nonNullDraftId);
          },
        );
      }

      final primaryFuture = uploadPrimary();
      final secondaryFuture = uploadSecondary();

      final primaryUpload = await primaryFuture;
      final secondaryUpload = await secondaryFuture;

      primary = 1;
      secondary = hasSecondary ? 1 : 0;

      final primaryUrl = primaryUpload.publicUrl.trim().isNotEmpty ? primaryUpload.publicUrl.trim() : mediaUrlPlanned;
      final secondaryUrl = secondaryUpload?.publicUrl.trim().isNotEmpty ?? false
          ? secondaryUpload!.publicUrl.trim()
          : imageUrlPlanned;

      emit(UploadStage.finalizing, draftId: nonNullDraftId);
      _throwIfCancelled(cancel, UploadStage.finalizing);

      await _retry<void>(
        () async {
          _throwIfCancelled(cancel, UploadStage.finalizing);
          await _finalize(
            type: type,
            draftId: nonNullDraftId,
            primaryUrl: primaryUrl,
            primaryPath: primaryUpload.path,
            secondaryUrl: secondaryUrl,
          );
        },
        maxAttempts: 3,
        shouldRetry: (e) => _isTransient(e),
      );

      emit(UploadStage.completed, draftId: nonNullDraftId);
      unawaited(
        JourneyService.instance.logEvent(
          eventType: 'upload_completed',
          eventKey: nonNullDraftId,
          metadata: {
            'media_type': type.name,
            'upload_id': uploadId,
          },
        ),
      );
      unawaited(_persistence.remove(uploadId));

      return UploadResult(
        success: true,
        uploadId: uploadId,
        draftId: nonNullDraftId,
        primaryUrl: primaryUrl,
        secondaryUrl: secondaryUrl,
        mediaType: type,
        duration: DateTime.now().difference(started),
      );
    } on UploadException catch (e, st) {
      final stage = e.stage;
      emit(stage, message: e.userMessage, error: e);
      developer.log('Upload failed uploadId=$uploadId stage=${stage.name} tech=${e.technicalMessage}', name: 'WEAFRICA.Upload', error: e, stackTrace: st);
      return UploadResult(
        success: false,
        uploadId: uploadId,
        error: e,
        mediaType: type,
        duration: DateTime.now().difference(started),
      );
    } catch (e, st) {
      final ex = UploadException(
        userMessage: 'WEAFRICA: Upload failed. Please try again.',
        technicalMessage: e.toString(),
        canRetry: true,
        stage: UploadStage.failed,
        originalError: e,
      );
      emit(UploadStage.failed, message: ex.userMessage, error: ex);
      developer.log('Unexpected upload error uploadId=$uploadId err=$e', name: 'WEAFRICA.Upload', error: e, stackTrace: st);
      return UploadResult(
        success: false,
        uploadId: uploadId,
        error: ex,
        mediaType: type,
        duration: DateTime.now().difference(started),
      );
    } finally {
      _active.remove(uploadId);
    }
  }

  Future<String?> _createDraft({
    required MediaType type,
    required String title,
    required String? caption,
    required String? artist,
    required String? genre,
    required String? country,
    required String? language,
    required String? category,
    required String? albumId,
    required String mediaUrlPlanned,
    required String mediaBucket,
    required String mediaPath,
    required String filePath,
    required String? imageUrlPlanned,
    required String imageBucket,
    required String? imagePath,
  }) async {
    final uri = Uri.parse(type == MediaType.song ? '${ApiEnv.baseUrl}/api/songs/create' : '${ApiEnv.baseUrl}/api/videos/create');

    final payload = <String, dynamic>{
      // Publish immediately so uploads appear in consumer feeds right away.
      // (The Edge API still supports draft uploads, but the product expectation
      // for DJ/Artist uploads is “upload => visible”.)
      'publish': true,
      'title': title,
      if ((caption ?? '').trim().isNotEmpty) 'caption': caption,
      if (type == MediaType.song) ...{
        if ((artist ?? '').trim().isNotEmpty) 'artist': artist,
        if ((genre ?? '').trim().isNotEmpty) 'genre': genre,
        if ((country ?? '').trim().isNotEmpty) 'country': country,
        if ((language ?? '').trim().isNotEmpty) 'language': language,
      },
      if (type == MediaType.video && (category ?? '').trim().isNotEmpty) 'category': category?.trim(),
      if (type == MediaType.song) 'audio_url': mediaUrlPlanned else 'video_url': mediaUrlPlanned,
      'file_path': filePath,
      ...?(imageUrlPlanned == null
          ? null
          : <String, dynamic>{
              'thumbnail_url': imageUrlPlanned,
              if (type == MediaType.song) 'artwork_url': imageUrlPlanned,
            }),
      if ((albumId ?? '').trim().isNotEmpty && type == MediaType.song) 'album_id': albumId,
      if (type == MediaType.song) 'audio_bucket': mediaBucket else 'video_bucket': mediaBucket,
      if (type == MediaType.song) 'audio_path': mediaPath else 'video_path': mediaPath,
      ...?(imagePath == null
          ? null
          : <String, dynamic>{
              'thumbnail_bucket': imageBucket,
              'thumbnail_path': imagePath,
              if (type == MediaType.song) 'artwork_bucket': imageBucket,
              if (type == MediaType.song) 'artwork_path': imagePath,
            }),
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Draft create failed (${res.statusCode})';
      String? errorCode;
      var upgradeRequired = false;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
          errorCode = decoded['error']?.toString().trim();
          upgradeRequired = decoded['upgrade_required'] == true ||
              errorCode == 'upload_limit_exceeded' ||
              errorCode == 'plan_upgrade_required' ||
              errorCode == 'feature_unavailable';
        }
      } catch (_) {
        final t = res.body.trim();
        if (t.isNotEmpty) msg = t;
      }

      final lower = msg.toLowerCase();
      String userMessage = 'WEAFRICA: Could not create draft. Please try again.';
      var canRetry = true;
      if (res.statusCode == 403 && upgradeRequired) {
        userMessage = msg.isEmpty ? 'WEAFRICA: Upgrade required to continue.' : 'WEAFRICA: $msg';
        canRetry = false;
      } else if (res.statusCode == 401 || (res.statusCode == 403 && lower.contains('creator'))) {
        userMessage = 'WEAFRICA: Creator account required. Please sign in as Artist/DJ and try again.';
        canRetry = false;
      } else if (res.statusCode == 404) {
        userMessage = 'WEAFRICA: Upload service not available. Please try again later.';
      }

      throw UploadException(
        userMessage: userMessage,
        technicalMessage: msg,
        canRetry: canRetry,
        stage: UploadStage.creatingDraft,
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final key = type == MediaType.song ? 'song_id' : 'video_id';
      final id = decoded[key];
      if (id is String && id.trim().isNotEmpty) return id.trim();
    }

    return null;
  }

  Future<void> _finalize({
    required MediaType type,
    required String draftId,
    required String primaryUrl,
    required String primaryPath,
    required String? secondaryUrl,
  }) async {
    final uri = Uri.parse(type == MediaType.song ? '${ApiEnv.baseUrl}/api/songs/finalize' : '${ApiEnv.baseUrl}/api/videos/finalize');

    final payload = <String, dynamic>{
      (type == MediaType.song ? 'song_id' : 'video_id'): draftId,
      (type == MediaType.song ? 'audio_url' : 'video_url'): primaryUrl,
      'file_path': primaryPath,
      ...?(secondaryUrl == null
          ? null
          : <String, dynamic>{
              'thumbnail_url': secondaryUrl,
              if (type == MediaType.song) 'artwork_url': secondaryUrl,
            }),
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    String msg = 'Finalize failed (${res.statusCode})';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
      }
    } catch (_) {
      final t = res.body.trim();
      if (t.isNotEmpty) msg = t;
    }

    throw UploadException(
      userMessage: 'WEAFRICA: Could not publish right now. Please try again.',
      technicalMessage: msg,
      canRetry: true,
      stage: UploadStage.finalizing,
    );
  }

  Future<void> dispose() async {
    await _events.close();
  }
}
