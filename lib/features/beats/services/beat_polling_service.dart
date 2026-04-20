import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import '../models/beat_models.dart';
import 'beat_assistant_api.dart';

class BeatPollingInfo {
  const BeatPollingInfo({
    required this.attempt,
    required this.nextDelay,
    required this.lastStatus,
  });

  final int attempt;
  final Duration nextDelay;
  final String? lastStatus;
}

/// Smart polling service with exponential backoff and jitter.
class BeatPollingService {
  BeatPollingService({BeatAssistantApi? api}) : _api = api ?? const BeatAssistantApi();

  final BeatAssistantApi _api;

  Timer? _timer;
  String? _jobId;
  int _attempt = 0;
  int _consecutiveErrors = 0;

  static const int _maxAttempts = 30;
  static const int _maxConsecutiveErrors = 6;
  static const Duration _baseDelay = Duration(seconds: 2);

  bool get isPolling => _timer != null;

  void startPolling({
    required String jobId,
    required void Function(BeatAudioJob job) onUpdate,
    required void Function(BeatPollingInfo info) onInfo,
    required void Function(Object error) onError,
    Future<BeatAudioStatusResponse> Function(String jobId)? loadStatus,
  }) {
    stopPolling();

    _jobId = jobId;
    _attempt = 0;
    _consecutiveErrors = 0;

    developer.log('Start polling for job $jobId', name: 'WEAFRICA.Beats.Polling');

    unawaited(_poll(onUpdate: onUpdate, onInfo: onInfo, onError: onError, loadStatus: loadStatus));
  }

  Future<void> _poll({
    required void Function(BeatAudioJob job) onUpdate,
    required void Function(BeatPollingInfo info) onInfo,
    required void Function(Object error) onError,
    Future<BeatAudioStatusResponse> Function(String jobId)? loadStatus,
  }) async {
    final jobId = _jobId;
    if (jobId == null || jobId.isEmpty) return;

    _timer?.cancel();

    try {
      final res = loadStatus == null ? await _api.audioMp3Status(jobId) : await loadStatus(jobId);
      _attempt++;
      _consecutiveErrors = 0;

      developer.log(
        'Poll attempt $_attempt for $jobId: ${res.job.status}',
        name: 'WEAFRICA.Beats.Polling',
      );

      onUpdate(res.job);

      final status = res.job.status;
      if (status == 'succeeded' || status == 'failed' || _attempt >= _maxAttempts) {
        stopPolling();
        return;
      }

      final delay = _calculateDelay(attempt: _attempt);
      onInfo(BeatPollingInfo(attempt: _attempt, nextDelay: delay, lastStatus: status));

      _timer = Timer(delay, () {
        unawaited(_poll(onUpdate: onUpdate, onInfo: onInfo, onError: onError, loadStatus: loadStatus));
      });
    } catch (e, st) {
      _attempt++;
      _consecutiveErrors++;

      developer.log(
        'Polling error (attempt $_attempt) for $jobId',
        name: 'WEAFRICA.Beats.Polling',
        error: e,
        stackTrace: st,
      );

      if (_attempt >= _maxAttempts || _consecutiveErrors >= _maxConsecutiveErrors) {
        onError(e);
        stopPolling();
        return;
      }

      final delay = _calculateDelay(attempt: _attempt);
      onInfo(BeatPollingInfo(attempt: _attempt, nextDelay: delay, lastStatus: null));
      _timer = Timer(delay, () {
        unawaited(_poll(onUpdate: onUpdate, onInfo: onInfo, onError: onError, loadStatus: loadStatus));
      });
    }
  }

  Duration _calculateDelay({required int attempt}) {
    // 2s, 4s, 8s, ... with a sensible cap.
    final multiplier = pow(2, max(0, attempt - 1)).toDouble();
    final baseMs = (_baseDelay.inMilliseconds * multiplier).round();
    final cappedMs = min(baseMs, const Duration(seconds: 20).inMilliseconds);

    // Jitter ±20%
    final jitter = (cappedMs * 0.2 * (Random().nextDouble() - 0.5)).round();
    final ms = max(1000, cappedMs + jitter);

    return Duration(milliseconds: ms);
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _jobId = null;
    _attempt = 0;
    _consecutiveErrors = 0;

    developer.log('Polling stopped', name: 'WEAFRICA.Beats.Polling');
  }

  void dispose() {
    stopPolling();
  }
}
