import 'dart:async';

import '../features/subscriptions/subscriptions_controller.dart';

/// In-memory skip-per-hour gate for consumer playback.
///
/// - Emit a warning when the user is near their hourly skip limit.
/// - Blocks the skip when the limit is reached.
///
/// Source of truth for the skip limit comes from `/api/subscriptions/me`
/// entitlements via [SubscriptionsController].
class PlaybackSkipsGate {
  PlaybackSkipsGate({
    int Function()? maxSkipsPerHourProvider,
    DateTime Function()? now,
  }) : _maxSkipsPerHourProvider =
           maxSkipsPerHourProvider ??
           (() => SubscriptionsController.instance.maxSkipsPerHour),
       _now = now ?? DateTime.now;

  static final PlaybackSkipsGate instance = PlaybackSkipsGate();

  static const Duration _window = Duration(hours: 1);
  static const int _nearLimitThreshold = 2;
  static const Duration _warningCooldown = Duration(hours: 2);

  final int Function() _maxSkipsPerHourProvider;
  final DateTime Function() _now;

  final StreamController<SkipGateEvent> _events =
      StreamController<SkipGateEvent>.broadcast();

  Stream<SkipGateEvent> get events => _events.stream;

  final List<DateTime> _skipTimestamps = <DateTime>[];

  DateTime? _lastWarningAt;
  DateTime? _lastDeniedAt;

  bool wasSkipDeniedRecently({Duration within = const Duration(seconds: 2)}) {
    final at = _lastDeniedAt;
    if (at == null) return false;
    return _now().difference(at) <= within;
  }

  /// Returns true when the skip should proceed.
  ///
  /// When false, the caller should not advance playback.
  bool tryConsumeUserSkip() {
    final limit = _maxSkipsPerHourProvider();
    if (limit < 0) return true; // unlimited

    final now = _now();
    _evictOld(now);

    final used = _skipTimestamps.length;
    if (used >= limit) {
      _lastDeniedAt = now;
      _emit(
        SkipGateEvent.blocked(
          used: used,
          limit: limit,
          remaining: 0,
        ),
      );
      return false;
    }

    _skipTimestamps.add(now);

    final remaining = (limit - (used + 1)).clamp(0, 100000000);
    if (remaining > 0 && remaining <= _nearLimitThreshold) {
      final lastWarn = _lastWarningAt;
      if (lastWarn == null || now.difference(lastWarn) >= _warningCooldown) {
        _lastWarningAt = now;
        _emit(
          SkipGateEvent.warning(
            used: used + 1,
            limit: limit,
            remaining: remaining,
            nearLimitLabel: _nearLimitLabel(remaining),
          ),
        );
      }
    }

    return true;
  }

  void reset() {
    _skipTimestamps.clear();
    _lastWarningAt = null;
    _lastDeniedAt = null;
  }

  Future<void> dispose() async {
    await _events.close();
  }

  void _emit(SkipGateEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  void _evictOld(DateTime now) {
    _skipTimestamps.removeWhere((ts) => now.difference(ts) >= _window);
  }

  String _nearLimitLabel(int remaining) {
    if (remaining == 1) return '1 skip left this hour';
    return '$remaining skips left this hour';
  }
}

enum SkipGateEventType { warning, blocked }

class SkipGateEvent {
  const SkipGateEvent._({
    required this.type,
    required this.used,
    required this.limit,
    required this.remaining,
    this.nearLimitLabel,
  });

  final SkipGateEventType type;
  final int used;
  final int limit;
  final int remaining;

  /// Optional: used to render a yellow “almost there” hint in the upgrade modal.
  final String? nearLimitLabel;

  factory SkipGateEvent.warning({
    required int used,
    required int limit,
    required int remaining,
    required String nearLimitLabel,
  }) {
    return SkipGateEvent._(
      type: SkipGateEventType.warning,
      used: used,
      limit: limit,
      remaining: remaining,
      nearLimitLabel: nearLimitLabel,
    );
  }

  factory SkipGateEvent.blocked({
    required int used,
    required int limit,
    required int remaining,
  }) {
    return SkipGateEvent._(
      type: SkipGateEventType.blocked,
      used: used,
      limit: limit,
      remaining: remaining,
    );
  }
}
