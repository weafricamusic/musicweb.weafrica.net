import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/utils/result.dart';
import '../../../../services/creator_finance_api.dart';
import '../../../../services/journey_milestone_service.dart';
import '../../../artist_dashboard/services/artist_identity_service.dart';
import '../models/dashboard_stats.dart';

class ArtistStatsRepository {
  ArtistStatsRepository({
    SupabaseClient? client,
    ArtistIdentityService? identity,
  })  : _client = client ?? Supabase.instance.client,
        _identity = identity ?? ArtistIdentityService(client: client);

  final SupabaseClient _client;
  final ArtistIdentityService _identity;

  Future<Result<DashboardStats>> getDashboardStats() async {
    try {
      final artistId = await _identity.resolveArtistId();
      final uid = _identity.currentFirebaseUid();
      if (artistId == null) {
        return Result.failure(Exception('WEAFRICA: No artist profile found'));
      }

      final rpcStats = await _tryRpcDashboardStats(artistId: artistId);
      if (rpcStats != null) {
        if (uid != null && uid.trim().isNotEmpty) {
          unawaited(
            JourneyMilestoneService.instance.captureCreatorStats(
              userId: uid.trim(),
              role: 'artist',
              totalPlays: rpcStats.totalPlays,
              followers: rpcStats.followers,
              totalEarnings: rpcStats.totalEarnings,
            ),
          );
        }
        return Result.success(rpcStats);
      }

      final artistRow = await _loadArtistRow(artistId);

      final followers = _readInt(artistRow, ['followers_count', 'follower_count', 'followers']) ?? 0;
      final plays = _readInt(artistRow, ['total_plays', 'plays_count', 'streams', 'total_streams']) ?? 0;

      final earnings = await _bestEffortTotalEarnings(uid: uid);
      final unreadMessages = await _bestEffortUnreadMessagesCount(artistId: artistId, uid: uid);
      final pendingNotifications = await _bestEffortNotificationsCount(uid: uid, artistId: artistId);
      final songsCount = await _bestEffortSongsCount(artistId: artistId, uid: uid);
      final videosCount = await _bestEffortVideosCount(artistId: artistId, uid: uid);

      developer.log('Loaded dashboard stats artist=$artistId', name: 'WEAFRICA.Dashboard');

      final stats = DashboardStats(
          followers: followers,
          totalPlays: plays,
          totalEarnings: earnings,
          unreadMessages: unreadMessages,
          pendingNotifications: pendingNotifications,
          songsCount: songsCount,
          videosCount: videosCount,
          battlesWon: 0,
          battlesLost: 0,
          rank: 0,
      );

      if (uid != null && uid.trim().isNotEmpty) {
        unawaited(
          JourneyMilestoneService.instance.captureCreatorStats(
            userId: uid.trim(),
            role: 'artist',
            totalPlays: stats.totalPlays,
            followers: stats.followers,
            totalEarnings: stats.totalEarnings,
          ),
        );
      }

      return Result.success(stats);
    } on PostgrestException catch (e, st) {
      developer.log('DB error loading dashboard stats', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load dashboard stats'));
    } catch (e, st) {
      developer.log('Unexpected error loading dashboard stats', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load dashboard stats'));
    }
  }

  Future<DashboardStats?> _tryRpcDashboardStats({required String artistId}) async {
    try {
      final resp = await _client.rpc(
        'get_artist_dashboard_stats',
        params: {'p_artist_id': artistId},
      );

      Map<String, dynamic>? map;
      if (resp is Map<String, dynamic>) {
        map = resp;
      } else if (resp is List && resp.isNotEmpty && resp.first is Map<String, dynamic>) {
        map = resp.first as Map<String, dynamic>;
      } else if (resp is String) {
        final decoded = jsonDecode(resp);
        if (decoded is Map<String, dynamic>) map = decoded;
      }

      if (map == null) return null;

      int readInt(String key) {
        final v = map![key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      double readDouble(String key) {
        final v = map![key];
        if (v is double) return v;
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '') ?? 0;
      }

      developer.log('Loaded dashboard stats via RPC artist=$artistId', name: 'WEAFRICA.Dashboard');

      return DashboardStats(
        followers: readInt('followers'),
        totalPlays: readInt('total_plays'),
        totalEarnings: readDouble('total_earnings'),
        unreadMessages: readInt('unread_messages'),
        pendingNotifications: 0,
        songsCount: readInt('songs_count'),
        videosCount: readInt('videos_count'),
        battlesWon: 0,
        battlesLost: 0,
        rank: 0,
      );
    } on PostgrestException catch (e, st) {
      // If the function isn't deployed yet (or RLS blocks it), fall back.
      developer.log('RPC get_artist_dashboard_stats unavailable', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return null;
    } catch (e, st) {
      developer.log('RPC get_artist_dashboard_stats failed', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadArtistRow(String artistId) async {
    final List<dynamic> rows = await _client.from('artists').select('*').eq('id', artistId).limit(1);
    if (rows.isNotEmpty && rows.first is Map<String, dynamic>) return rows.first as Map<String, dynamic>;
    return null;
  }

  int? _readInt(Map<String, dynamic>? row, List<String> keys) {
    if (row == null) return null;
    for (final k in keys) {
      final v = row[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse(v?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  Future<double> _bestEffortTotalEarnings({required String? uid}) async {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return 0;

    try {
      final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
      if (summary.userId.trim().isEmpty || summary.userId.trim() != u) return 0;
      return summary.totalEarned;
    } catch (_) {
      // ignore here; return 0
    }
    return 0;
  }

  Future<int> _bestEffortUnreadMessagesCount({required String artistId, required String? uid}) async {
    try {
      dynamic q = _client.from('messages').select('id');
      q = q.eq('read', false);
      q = q.eq('artist_id', artistId);
      final List<dynamic> rows = await q.limit(500);
      return rows.length;
    } catch (_) {
      try {
        final u = (uid ?? '').trim();
        if (u.isEmpty) return 0;
        final List<dynamic> rows = await _client.from('messages').select('id').eq('read', false).eq('artist_uid', u).limit(500);
        return rows.length;
      } catch (_) {
        // ignore
      }
      return 0;
    }
  }

  Future<int> _bestEffortNotificationsCount({required String? uid, required String artistId}) async {
    // Schema varies; keep centralized here.
    try {
      final List<dynamic> rows = await _client.from('notifications').select('id').order('created_at', ascending: false).limit(500);
      return rows.length;
    } catch (_) {
      // ignore
    }
    return 0;
  }

  Future<int> _bestEffortSongsCount({required String artistId, required String? uid}) async {
    try {
      final List<dynamic> rows = await _client.from('songs').select('id').eq('artist_id', artistId).limit(1000);
      return rows.length;
    } catch (_) {
      // ignore
    }
    // Legacy fallback: songs.artist == uid
    final u = (uid ?? '').trim();
    if (u.isEmpty) return 0;
    try {
      final List<dynamic> rows = await _client.from('songs').select('id').eq('artist', u).limit(1000);
      return rows.length;
    } catch (_) {
      // ignore
    }
    return 0;
  }

  Future<int> _bestEffortVideosCount({required String artistId, required String? uid}) async {
    try {
      final List<dynamic> rows = await _client.from('videos').select('id').eq('artist_id', artistId).limit(1000);
      return rows.length;
    } catch (_) {
      // ignore
    }
    final u = (uid ?? '').trim();
    if (u.isEmpty) return 0;
    try {
      final List<dynamic> rows = await _client.from('videos').select('id').eq('uploader_id', u).limit(1000);
      return rows.length;
    } catch (_) {
      // ignore
    }
    return 0;
  }
}
