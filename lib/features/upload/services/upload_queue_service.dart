import 'dart:async';

import '../models/upload_queue_item.dart';
import '../models/upload_stage.dart';
import '../models/upload_status.dart';
import 'upload_queue.dart';
import 'upload_state_machine.dart';

class UploadQueueSnapshot {
  const UploadQueueSnapshot({
    required this.queued,
    required this.active,
  });

  final int queued;
  final int active;
}

/// UI-facing adapter for the upload pipeline.
///
/// The actual upload logic lives in [UploadStateMachine]. This service provides
/// simple, screen-friendly data for: queue status + persisted progress.
class UploadQueueService {
  UploadQueueService({
    UploadStateMachine? machine,
    UploadQueue? queue,
  })  : _machine = machine ?? UploadStateMachine.instance,
        _queue = queue ?? UploadQueue.instance;

  final UploadStateMachine _machine;
  final UploadQueue _queue;

  Stream<UploadQueueSnapshot> watchQueueSnapshot() {
    // Emit immediately + whenever queue changes.
    final controller = StreamController<UploadQueueSnapshot>.broadcast();

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        UploadQueueSnapshot(
          queued: _queue.queueLength,
          active: _queue.activeUploads,
        ),
      );
    }

    emit();
    final sub = _queue.queueUpdates.listen((_) => emit());

    controller.onCancel = () {
      unawaited(sub.cancel());
      unawaited(controller.close());
    };

    return controller.stream;
  }

  Future<List<UploadQueueItem>> loadPersisted({int limit = 6}) async {
    final statuses = await _machine.loadPendingUploads();
    statuses.sort((a, b) => b.updatedAtUtcMs.compareTo(a.updatedAtUtcMs));

    return statuses.take(limit).map(_map).toList(growable: false);
  }

  UploadQueueItem _map(UploadStatus s) {
    final progress = (s.overallProgress ?? 0).clamp(0.0, 1.0).toDouble();
    return UploadQueueItem(
      uploadId: s.uploadId,
      mediaType: s.mediaType,
      stage: s.stage.name,
      message: s.message,
      progress: progress,
      updatedAtUtcMs: s.updatedAtUtcMs,
      canRetry: s.error?.canRetry ?? (s.stage == UploadStage.failed),
    );
  }
}
