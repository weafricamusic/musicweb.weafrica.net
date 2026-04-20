// WEAFRICA Music — Legacy Wrapper (Backwards compatible)

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/media_type.dart';
import 'models/upload_event.dart';
import 'models/upload_exception.dart';
import 'models/upload_stage.dart';
import 'models/upload_result.dart';
import '../../app/media/upload_media_compressor.dart' show UploadCompressionPreset;
import 'services/upload_state_machine.dart';

class DraftUploadUpdate {
  const DraftUploadUpdate({
    required this.mediaType,
    required this.stage,
    required this.overallProgress,
    required this.primaryProgress,
    required this.secondaryProgress,
    this.draftId,
  });

  final MediaType mediaType;
  final String stage;
  final double overallProgress;
  final double primaryProgress;
  final double secondaryProgress;
  final String? draftId;
}

class DraftUploadResult {
  const DraftUploadResult({
    required this.mediaType,
    required this.draftId,
    required this.primaryUrl,
    this.secondaryUrl,
    this.uploadId,
  });

  final MediaType mediaType;
  final String draftId;
  final String primaryUrl;
  final String? secondaryUrl;
  final String? uploadId;

  Map<String, dynamic> toJson() => {
        'media_type': mediaType.name,
        'id': draftId,
        'primary_url': primaryUrl,
        if (secondaryUrl != null) 'secondary_url': secondaryUrl,
        if (uploadId != null) 'upload_id': uploadId,
      };
}

/// Legacy API expected by existing upload screens.
///
/// Internally delegates to [UploadStateMachine].
class DraftUploader {
  DraftUploader({SupabaseClient? supabaseClient}) {
    // Constructor kept for backwards compatibility.
    if (supabaseClient != null) {
      _machine = UploadStateMachine(supabaseClient: supabaseClient);
    }
  }

  UploadStateMachine _machine = UploadStateMachine.instance;

  /// Cancels an active upload.
  bool cancelUpload(String uploadId) => _machine.cancelUpload(uploadId);

  Future<DraftUploadResult> uploadSong({
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
    void Function(DraftUploadUpdate update)? onUpdate,
  }) async {
    UploadResult result;
    result = await _machine.uploadSong(
      title: title,
      artist: artist,
      genre: genre,
      country: country,
      language: language,
      audioFile: audioFile,
      artworkFile: artworkFile,
      albumId: albumId,
      reuseDraftId: reuseDraftId,
      compressionPreset: compressionPreset,
      onEvent: (e) => _mapLegacy(
        e,
        mediaType: MediaType.song,
        hasSecondary: artworkFile != null,
        onUpdate: onUpdate,
      ),
    );

    if (!result.success) {
      throw result.error ?? const UploadException(
        userMessage: 'WEAFRICA: Upload failed. Please try again.',
        technicalMessage: 'UploadResult.success=false',
        canRetry: true,
        stage: UploadStage.failed,
      );
    }

    return DraftUploadResult(
      mediaType: MediaType.song,
      draftId: result.draftId ?? '',
      primaryUrl: result.primaryUrl ?? '',
      secondaryUrl: result.secondaryUrl,
      uploadId: result.uploadId,
    );
  }

  Future<DraftUploadResult> uploadVideo({
    required String title,
    required PlatformFile videoFile,
    PlatformFile? thumbnailFile,
    String? reuseDraftId,
    String? category,
    String? creatorProvisionIntent,
    UploadCompressionPreset compressionPreset = UploadCompressionPreset.balanced,
    void Function(DraftUploadUpdate update)? onUpdate,
  }) async {
    // creatorProvisionIntent retained as argument for compatibility.
    // The state machine doesn't currently use it.
    final result = await _machine.uploadVideo(
      title: title,
      videoFile: videoFile,
      thumbnailFile: thumbnailFile,
      reuseDraftId: reuseDraftId,
      category: category,
      compressionPreset: compressionPreset,
      onEvent: (e) => _mapLegacy(
        e,
        mediaType: MediaType.video,
        hasSecondary: thumbnailFile != null,
        onUpdate: onUpdate,
      ),
    );

    if (!result.success) {
      throw result.error ?? const UploadException(
        userMessage: 'WEAFRICA: Upload failed. Please try again.',
        technicalMessage: 'UploadResult.success=false',
        canRetry: true,
        stage: UploadStage.failed,
      );
    }

    return DraftUploadResult(
      mediaType: MediaType.video,
      draftId: result.draftId ?? '',
      primaryUrl: result.primaryUrl ?? '',
      secondaryUrl: result.secondaryUrl,
      uploadId: result.uploadId,
    );
  }

  void _mapLegacy(
    UploadEvent event, {
    required MediaType mediaType,
    required bool hasSecondary,
    required void Function(DraftUploadUpdate update)? onUpdate,
  }) {
    if (onUpdate == null) return;

    final overall = (event.progress ?? 0).clamp(0.0, 1.0).toDouble();
    final primary = (event.primaryProgress ?? overall).clamp(0.0, 1.0).toDouble();
    final secondary = hasSecondary ? (event.secondaryProgress ?? 0).clamp(0.0, 1.0).toDouble() : 0.0;

    onUpdate(
      DraftUploadUpdate(
        mediaType: mediaType,
        stage: event.message,
        overallProgress: overall,
        primaryProgress: primary,
        secondaryProgress: secondary,
        draftId: event.draftId,
      ),
    );
  }
}
