/// Helper utilities for live streams.
class LiveHelpers {
  /// Generate a unique channel name for a solo stream.
  static String soloChannelName(String userId) {
    return 'solo_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate a unique channel name for a battle stream.
  static String battleChannelName(String userId1, String userId2) {
    return 'battle_${userId1}_${userId2}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Format seconds to mm:ss.
  static String formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
