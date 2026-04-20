import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/user_role.dart';
import '../../artist_dashboard/services/artist_identity_service.dart';
import '../../../services/creator_finance_api.dart';

@immutable
class CreatorStats {
  const CreatorStats({
    required this.followers,
    required this.streams,
    required this.earningsCoins,
  });

  final int? followers;
  final int? streams;
  final int? earningsCoins;
}

class CreatorStatsService {
  CreatorStatsService({
    SupabaseClient? client,
    CreatorFinanceApi? finance,
    ArtistIdentityService? artistIdentity,
    FirebaseAuth? auth,
  })  : _client = client ?? Supabase.instance.client,
        _finance = finance ?? const CreatorFinanceApi(),
        _artistIdentity = artistIdentity ?? ArtistIdentityService(client: client),
        _auth = auth ?? FirebaseAuth.instance;

  final SupabaseClient _client;
  final CreatorFinanceApi _finance;
  final ArtistIdentityService _artistIdentity;
  final FirebaseAuth _auth;

  Future<CreatorStats> getStats({required UserRole role}) async {
    final uid = _auth.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      throw StateError('Not signed in');
    }

    final earningsCoins = await _bestEffortEarningsCoins(uid: uid);

    switch (role) {
      case UserRole.artist:
        final artistId = await _artistIdentity.resolveArtistId();
        final followers = await _bestEffortArtistFollowers(artistId: artistId);
        final streams = await _bestEffortArtistStreams(artistId: artistId, uid: uid);
        return CreatorStats(
          followers: followers,
          streams: streams,
          earningsCoins: earningsCoins,
        );
      case UserRole.dj:
        final followers = await _bestEffortDjFollowers(uid: uid);
        final streams = await _bestEffortDjStreams(uid: uid);
        return CreatorStats(
          followers: followers,
          streams: streams,
          earningsCoins: earningsCoins,
        );
      case UserRole.consumer:
        return CreatorStats(
          followers: null,
          streams: null,
          earningsCoins: earningsCoins,
        );
    }
  }

  Future<int?> _bestEffortEarningsCoins({required String uid}) async {
    final summary = await _finance.fetchMyWalletSummary();
    final summaryUid = summary.userId.trim();
    if (summaryUid.isNotEmpty && summaryUid != uid.trim()) {
      throw StateError('Wallet summary user mismatch');
    }
    return summary.totalEarned.round();
  }

  Future<int?> _bestEffortArtistFollowers({required String? artistId}) async {
    final id = (artistId ?? '').trim();
    if (id.isEmpty) return null;

    final List<dynamic> rows = await _client
        .from('followers')
        .select('count:id.count()')
        .eq('artist_id', id);

    if (rows.isNotEmpty && rows.first is Map) {
      final m = (rows.first as Map).map((k, v) => MapEntry(k.toString(), v));
      return _toInt(m['count']) ?? 0;
    }
    return 0;
  }

  Future<int?> _bestEffortArtistStreams({required String? artistId, required String uid}) async {
    final id = (artistId ?? '').trim();
    if (id.isEmpty) return null;
    final sum = await _sumInt(
      table: 'songs',
      select: 'sum:streams.sum()',
      filterKey: 'artist_id',
      filterValue: id,
    );
    return sum;
  }

  Future<int?> _bestEffortDjFollowers({required String uid}) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final List<dynamic> rows = await _client
        .from('dj_profile')
        .select('followers_count')
        .eq('dj_uid', u)
        .limit(1);
    if (rows.isNotEmpty && rows.first is Map) {
      final m = (rows.first as Map).map((k, v) => MapEntry(k.toString(), v));
      return _toInt(m['followers_count']) ?? 0;
    }
    return 0;
  }

  Future<int?> _bestEffortDjStreams({required String uid}) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final sum = await _sumInt(
      table: 'dj_sets',
      select: 'sum:plays.sum()',
      filterKey: 'dj_uid',
      filterValue: u,
    );
    return sum;
  }

  Future<int> _sumInt({
    required String table,
    required String select,
    required String filterKey,
    required String filterValue,
  }) async {
    final List<dynamic> rows = await _client.from(table).select(select).eq(filterKey, filterValue);

    if (rows.isEmpty || rows.first is! Map) return 0;
    final m = (rows.first as Map).map((k, v) => MapEntry(k.toString(), v));
    return _toInt(m['sum']) ?? 0;
  }

  int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
