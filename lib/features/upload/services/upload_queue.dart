import 'dart:async';
import 'dart:developer' as developer;

import '../models/upload_exception.dart';
import '../models/upload_stage.dart';

typedef UploadTask<T> = Future<T> Function();

class QueuedUpload<T> {
  QueuedUpload({
    required this.id,
    required this.name,
    required this.task,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final UploadTask<T> task;
  final DateTime createdAt;
  final Completer<T> completer = Completer<T>();

  bool cancelledBeforeStart = false;
}

class UploadQueue {
  UploadQueue._internal();
  static final UploadQueue instance = UploadQueue._internal();

  final List<QueuedUpload<dynamic>> _queue = <QueuedUpload<dynamic>>[];
  final _queueController = StreamController<List<QueuedUpload<dynamic>>>.broadcast();

  static const int _maxConcurrent = 2;
  int _active = 0;
  bool _draining = false;

  Stream<List<QueuedUpload<dynamic>>> get queueUpdates => _queueController.stream;

  int get queueLength => _queue.length;
  int get activeUploads => _active;

  Future<T> enqueue<T>({
    required String id,
    required String name,
    required UploadTask<T> task,
  }) {
    final item = QueuedUpload<T>(id: id, name: name, task: task);
    _queue.add(item);
    _queueController.add(List<QueuedUpload<dynamic>>.unmodifiable(_queue));

    developer.log('Queued upload name=$name id=$id (queue=${_queue.length})', name: 'WEAFRICA.UploadQueue');

    unawaited(_drain());
    return item.completer.future;
  }

  bool cancelQueued(String id) {
    for (final item in _queue) {
      if (item.id == id && !item.cancelledBeforeStart) {
        item.cancelledBeforeStart = true;
        return true;
      }
    }
    return false;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;

    try {
      while (_queue.isNotEmpty && _active < _maxConcurrent) {
        final next = _queue.removeAt(0);
        _queueController.add(List<QueuedUpload<dynamic>>.unmodifiable(_queue));

        if (next.cancelledBeforeStart) {
          if (!next.completer.isCompleted) {
            next.completer.completeError(
              const UploadException(
                userMessage: 'Upload cancelled',
                technicalMessage: 'Cancelled before start',
                canRetry: true,
                stage: UploadStage.cancelled,
              ),
            );
          }
          continue;
        }

        _active++;
        unawaited(_execute(next));
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _execute(QueuedUpload<dynamic> upload) async {
    try {
      developer.log('Starting upload name=${upload.name} id=${upload.id}', name: 'WEAFRICA.UploadQueue');
      final result = await upload.task();
      if (!upload.completer.isCompleted) upload.completer.complete(result);
    } catch (e, st) {
      if (!upload.completer.isCompleted) upload.completer.completeError(e, st);
      developer.log('Upload failed name=${upload.name} id=${upload.id}: $e', name: 'WEAFRICA.UploadQueue', error: e, stackTrace: st);
    } finally {
      _active = (_active - 1).clamp(0, 1 << 30).toInt();
      unawaited(_drain());
    }
  }

  void dispose() {
    _queueController.close();
  }
}
