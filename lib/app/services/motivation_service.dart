import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class MotivationService {
  static const String _lastShownDateKey = 'motivation.lastShownDate';
  static const String _countTodayKey = 'motivation.countToday';
  static const String _lastMessageIndexKey = 'motivation.lastMessageIndex';

  final SharedPreferences _prefs;

  MotivationService(this._prefs);

  int _dateKey(DateTime now) => (now.year * 10000) + (now.month * 100) + now.day;

  /// Returns whether a motivation overlay can be shown today.
  ///
  /// This enforces a per-local-day maximum. It also resets the daily counter
  /// when the calendar date changes.
  Future<bool> shouldShowMotivation({int maxPerDay = 1, DateTime? now}) async {
    final t = now ?? DateTime.now();
    final todayKey = _dateKey(t);

    final lastShownKey = _prefs.getInt(_lastShownDateKey) ?? -1;
    if (lastShownKey != todayKey) {
      await _prefs.setInt(_lastShownDateKey, todayKey);
      await _prefs.setInt(_countTodayKey, 0);
      return true;
    }

    final countToday = _prefs.getInt(_countTodayKey) ?? 0;
    return countToday < maxPerDay;
  }

  Future<void> recordMotivationShown() async {
    final countToday = _prefs.getInt(_countTodayKey) ?? 0;
    await _prefs.setInt(_countTodayKey, countToday + 1);
  }

  /// Returns an index in [0, totalMessages), avoiding the last index when
  /// possible.
  Future<int> getNextMessageIndex(int totalMessages) async {
    if (totalMessages <= 0) return 0;
    if (totalMessages == 1) {
      await _prefs.setInt(_lastMessageIndexKey, 0);
      return 0;
    }

    final lastIndex = _prefs.getInt(_lastMessageIndexKey) ?? -1;
    final rng = Random(DateTime.now().microsecondsSinceEpoch);
    var nextIndex = rng.nextInt(totalMessages);
    if (nextIndex == lastIndex) {
      nextIndex = (nextIndex + 1) % totalMessages;
    }

    await _prefs.setInt(_lastMessageIndexKey, nextIndex);
    return nextIndex;
  }
}
