import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tracks/track.dart';
import '../models/artist_dashboard_models.dart';
import '../../../services/creator_finance_api.dart';
import 'artist_identity_service.dart';
import '../../artist/dashboard/services/dashboard_content_service.dart';
import '../../artist/dashboard/services/dashboard_notification_service.dart';
import '../../artist/dashboard/services/dashboard_stats_service.dart';
import '../../artist/dashboard/repositories/artist_content_repository.dart';
import '../../artist/dashboard/repositories/artist_notification_repository.dart';
import '../../artist/dashboard/repositories/artist_stats_repository.dart';

class ArtistDashboardService {
  ArtistDashboardService({
    SupabaseClient? client,
    ArtistIdentityService? identity,
  })  : _client = client ?? Supabase.instance.client,
        _identity = identity ?? ArtistIdentityService(client: client ?? Supabase.instance.client) {
    _stats = DashboardStatsService(
      repository: ArtistStatsRepository(client: _client, identity: _identity),
    );
    _content = DashboardContentService(
      repository: ArtistContentRepository(client: _client, identity: _identity),
    );
    _notifications = DashboardNotificationService(
      repository: ArtistNotificationRepository(client: _client),
    );
  }

  final SupabaseClient _client;
  final ArtistIdentityService _identity;

  late final DashboardStatsService _stats;
  late final DashboardContentService _content;
  late final DashboardNotificationService _notifications;

  Future<ArtistDashboardHomeData> loadHome({int recentLimit = 5}) async {
    // Legacy facade used by ArtistDashboardHomeScreen.
    // Internally delegates to the new dashboard module.
    final artistId = await _identity.resolveArtistId();
    if (artistId == null) {
      developer.log('No artistId for dashboard home', name: 'WEAFRICA.Dashboard');
      return const ArtistDashboardHomeData(
        followersCount: 0,
        totalPlays: 0,
        totalEarnings: 0,
        coinBalance: 0,
        recentSongs: <Track>[],
        recentVideos: <ArtistVideoItem>[],
        notificationsCount: 0,
        recentNotifications: <ArtistNotificationItem>[],
        unreadMessagesCount: 0,
      );
    }

    final statsResult = await _stats.get();
    final songsResult = await _content.getRecentSongs(limit: recentLimit, offset: 0);
    final videosResult = await _content.getRecentVideos(limit: recentLimit, offset: 0);
    final notifCountResult = await _notifications.count();
    final notifRecentResult = await _notifications.listRecent(limit: 3, offset: 0);

    final stats = statsResult.data;
    final followersCount = stats?.followers ?? 0;
    final totalPlays = stats?.totalPlays ?? 0;
    final totalEarnings = stats?.totalEarnings ?? 0;
    final unreadMessagesCount = stats?.unreadMessages ?? 0;

    // Best-effort: surface current coin balance on the dashboard.
    double coinBalance = 0;
    try {
      final uid = _identity.currentFirebaseUid();
      final u = (uid ?? '').trim();
      if (u.isNotEmpty) {
        final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
        if (summary.userId.trim() == u) {
          coinBalance = summary.coinBalance;
        }
      }
    } catch (_) {
      // ignore
    }

    final recentSongs = songsResult.data ?? const <Track>[];

    // Preserve existing UI model type for videos.
    final recentVideos = (videosResult.data ?? const [])
        .map(
          (v) => ArtistVideoItem(
            id: v.id,
            title: v.title,
            thumbnailUrl: v.thumbnailUrl,
            createdAt: v.createdAt,
          ),
        )
        .toList(growable: false);

    final notificationsCount = notifCountResult.data ?? 0;
    final recentNotifications = (notifRecentResult.data ?? const [])
        .map((n) => ArtistNotificationItem(title: n.title, body: n.body))
        .toList(growable: false);

    return ArtistDashboardHomeData(
      followersCount: followersCount,
      totalPlays: totalPlays,
      totalEarnings: totalEarnings,
      coinBalance: coinBalance,
      recentSongs: recentSongs,
      recentVideos: recentVideos,
      notificationsCount: notificationsCount,
      recentNotifications: recentNotifications,
      unreadMessagesCount: unreadMessagesCount,
    );
  }
}
