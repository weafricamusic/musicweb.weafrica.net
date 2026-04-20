import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'journey_service.dart';

class JourneyMilestoneService {
  JourneyMilestoneService._();

  static final JourneyMilestoneService instance = JourneyMilestoneService._();

  static const Map<String, List<int>> _thresholds = <String, List<int>>{
    'plays': <int>[100, 1000],
    'followers': <int>[10, 50],
    'earnings': <int>[1000, 2500],
  };

  Future<void> captureCreatorStats({
    required String userId,
    required String role,
    required int totalPlays,
    required int followers,
    required num totalEarnings,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedUserId.isEmpty || normalizedRole.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    await _captureMetric(
      prefs: prefs,
      userId: normalizedUserId,
      role: normalizedRole,
      metric: 'plays',
      currentValue: totalPlays,
    );
    await _captureMetric(
      prefs: prefs,
      userId: normalizedUserId,
      role: normalizedRole,
      metric: 'followers',
      currentValue: followers,
    );
    await _captureMetric(
      prefs: prefs,
      userId: normalizedUserId,
      role: normalizedRole,
      metric: 'earnings',
      currentValue: totalEarnings.floor(),
    );
  }

  Future<void> _captureMetric({
    required SharedPreferences prefs,
    required String userId,
    required String role,
    required String metric,
    required int currentValue,
  }) async {
    final thresholds = _thresholds[metric] ?? const <int>[];
    if (thresholds.isEmpty || currentValue <= 0) return;

    final key = 'journey.milestone.v1:$role:$userId:$metric';
    final lastReported = prefs.getInt(key) ?? 0;
    final newlyReached = thresholds.where((threshold) => threshold > lastReported && currentValue >= threshold).toList(growable: false);
    if (newlyReached.isEmpty) return;

    for (final threshold in newlyReached) {
      unawaited(
        JourneyService.instance.logEvent(
          eventType: 'milestone_reached',
          eventKey: '$role:$metric:$threshold',
          metadata: <String, Object?>{
            'role': role,
            'metric': metric,
            'threshold': threshold,
            'current_value': currentValue,
          },
        ),
      );
    }

    await prefs.setInt(key, newlyReached.last);
  }
}