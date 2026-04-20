import 'package:flutter/foundation.dart';

import '../../tracks/track.dart';

@immutable
class ArtistVideoItem {
  const ArtistVideoItem({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? thumbnailUrl;
  final DateTime? createdAt;

  factory ArtistVideoItem.fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final titleRaw = (row['title'] ?? row['name'] ?? '').toString().trim();
    final title = titleRaw.isEmpty ? 'Untitled video' : titleRaw;

    final thumbRaw = (row['thumbnail_url'] ?? row['thumbnail'] ?? row['image_url'] ?? '').toString().trim();
    final thumbnailUrl = thumbRaw.isEmpty ? null : thumbRaw;

    DateTime? createdAt;
    final createdAtRaw = row['created_at'] ?? row['createdAt'];
    if (createdAtRaw != null) createdAt = DateTime.tryParse(createdAtRaw.toString());

    return ArtistVideoItem(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      createdAt: createdAt,
    );
  }
}

@immutable
class ArtistNotificationItem {
  const ArtistNotificationItem({required this.title, required this.body});

  final String title;
  final String body;

  factory ArtistNotificationItem.fromSupabase(Map<String, dynamic> row) {
    final title = (row['title'] ?? row['type'] ?? 'Notification').toString();
    final body = (row['body'] ?? row['message'] ?? '').toString();
    return ArtistNotificationItem(title: title, body: body);
  }
}

@immutable
class ArtistDashboardHomeData {
  const ArtistDashboardHomeData({
    required this.followersCount,
    required this.totalPlays,
    required this.totalEarnings,
    required this.coinBalance,
    required this.recentSongs,
    required this.recentVideos,
    required this.notificationsCount,
    required this.recentNotifications,
    required this.unreadMessagesCount,
  });

  final int followersCount;
  final int totalPlays;
  final double totalEarnings;
  final double coinBalance;
  final List<Track> recentSongs;
  final List<ArtistVideoItem> recentVideos;
  final int notificationsCount;
  final List<ArtistNotificationItem> recentNotifications;
  final int unreadMessagesCount;
}
