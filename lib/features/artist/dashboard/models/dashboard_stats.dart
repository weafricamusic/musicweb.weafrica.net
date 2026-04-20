import 'package:flutter/foundation.dart';

@immutable
class DashboardStats {
  const DashboardStats({
    required this.followers,
    required this.totalPlays,
    required this.totalEarnings,
    required this.unreadMessages,
    required this.pendingNotifications,
    required this.songsCount,
    required this.videosCount,
    required this.battlesWon,
    required this.battlesLost,
    required this.rank,
  });

  final int followers;
  final int totalPlays;
  final double totalEarnings;
  final int unreadMessages;
  final int pendingNotifications;
  final int songsCount;
  final int videosCount;
  final int battlesWon;
  final int battlesLost;
  final double rank;

  int get totalBattles => battlesWon + battlesLost;
  double get winRate => totalBattles > 0 ? (battlesWon / totalBattles) * 100 : 0;

  Map<String, dynamic> toJson() => {
        'followers': followers,
        'total_plays': totalPlays,
        'total_earnings': totalEarnings,
        'unread_messages': unreadMessages,
        'pending_notifications': pendingNotifications,
        'songs_count': songsCount,
        'videos_count': videosCount,
        'battles_won': battlesWon,
        'battles_lost': battlesLost,
        'rank': rank,
      };
}

@immutable
class StatsDataPoint {
  const StatsDataPoint({required this.timestamp, required this.value});
  final DateTime timestamp;
  final double value;
}

@immutable
class HistoricalStats {
  const HistoricalStats({
    required this.followersHistory,
    required this.playsHistory,
    required this.earningsHistory,
  });

  final List<StatsDataPoint> followersHistory;
  final List<StatsDataPoint> playsHistory;
  final List<StatsDataPoint> earningsHistory;
}
