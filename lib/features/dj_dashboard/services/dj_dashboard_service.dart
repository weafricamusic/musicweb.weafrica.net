import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/dj_dashboard_models.dart';
import '../../../services/creator_finance_api.dart';
import '../../../services/journey_milestone_service.dart';

class DjDashboardService {
  final SupabaseClient _supabase;

  DjDashboardService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Future<DjDashboardHomeData> loadHome({required String djUid}) async {
    final profileFuture = getProfile(djUid: djUid);
    final setsFuture = listSets(djUid: djUid, limit: 100);
    final inboxFuture = _supabase
        .from('messages')
      .select('*')
        .eq('dj_uid', djUid)
        .order('created_at', ascending: false)
        .limit(200);
    final boostsFuture = _supabase
        .from('boosts')
        .select('id')
        .eq('dj_uid', djUid)
        .limit(200);
    final earningsFuture = bestEffortTotalEarnings(djUid: djUid);
    final coinBalanceFuture = bestEffortCoinBalance(djUid: djUid);
    final upcomingLivesFuture = listUpcomingLiveSchedule(djUid: djUid, limit: 3)
      .catchError((_) => const <DjEvent>[]);

    final results = await Future.wait<dynamic>([
      profileFuture,
      setsFuture,
      inboxFuture,
      boostsFuture,
      earningsFuture,
      coinBalanceFuture,
      upcomingLivesFuture,
    ]);

    final profile = results[0] as DjProfile?;
    final sets = results[1] as List<DjSet>;
    final inbox = results[2] as List<dynamic>;
    final boosts = results[3] as List<dynamic>;
    final earnings = results[4] as num;
    final coins = results[5] as num;
    final upcomingLives = results[6] as List<DjEvent>;

    var totalPlays = 0;
    for (final s in sets) {
      totalPlays += s.plays;
    }

    final inboxMessages = inbox
        .whereType<Map<String, dynamic>>()
        .map(DjMessage.fromRow)
        .toList(growable: false);

    final unread = inboxMessages.where((m) => !m.isRead).length;

    final boostsCount = boosts.length;

    final data = DjDashboardHomeData(
      totalPlays: totalPlays,
      followersCount: profile?.followersCount ?? 0,
      totalEarnings: earnings,
      coinBalance: coins,
      setsCount: sets.length,
      unreadMessagesCount: unread,
      boostsCount: boostsCount,
      recentSets: sets.take(4).toList(growable: false),
      upcomingLives: upcomingLives,
      recentInbox: inboxMessages.take(3).toList(growable: false),
    );

    unawaited(
      JourneyMilestoneService.instance.captureCreatorStats(
        userId: djUid,
        role: 'dj',
        totalPlays: data.totalPlays,
        followers: data.followersCount,
        totalEarnings: data.totalEarnings,
      ),
    );

    return data;
  }

  Future<DjProfile?> getProfile({required String djUid}) async {
    final rows = await _supabase
        .from('dj_profile')
        .select('*')
        .eq('dj_uid', djUid)
        .limit(1);

    final list = (rows as List<dynamic>);
    if (list.isNotEmpty) return DjProfile.fromRow(list.first as Map<String, dynamic>);
    return null;
  }

  Future<DjProfile> upsertProfile({
    required String djUid,
    required String? stageName,
    required String? country,
    required String? bio,
    required String? profilePhoto,
    required String? bankAccount,
    required String? mobileMoneyPhone,
  }) async {
    final row = {
      'dj_uid': djUid,
      'stage_name': stageName,
      'country': country,
      'bio': bio,
      'profile_photo': profilePhoto,
      'bank_account': bankAccount,
      'mobile_money_phone': mobileMoneyPhone,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final rows = await _supabase
        .from('dj_profile')
        .upsert(row, onConflict: 'dj_uid')
        .select('*')
        .limit(1);

    return DjProfile.fromRow((rows as List).first as Map<String, dynamic>);
  }

  Future<List<DjSet>> listSets({required String djUid, int limit = 50}) async {
    final rows = await _supabase
        .from('dj_sets')
        .select('*')
        .eq('dj_uid', djUid)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DjSet.fromRow)
        .toList();
  }

  Future<DjSet> createSet({
    required String djUid,
    required String title,
    required String audioUrl,
    required String? genre,
    required int? durationSeconds,
  }) async {
    final rows = await _supabase
        .from('dj_sets')
        .insert({
          'dj_uid': djUid,
          'title': title,
          'audio_url': audioUrl,
          'genre': genre,
          'duration': durationSeconds,
        })
        .select('*')
        .limit(1);

    return DjSet.fromRow((rows as List).first as Map<String, dynamic>);
  }

  Future<void> deleteSet({required String setId}) async {
    await _supabase.from('dj_sets').delete().eq('id', setId);
  }

  Future<List<DjPlaylist>> listPlaylists({required String djUid, int limit = 50}) async {
    final rows = await _supabase
        .from('dj_playlists')
        .select('*')
        .eq('dj_uid', djUid)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DjPlaylist.fromRow)
        .toList();
  }

  Future<DjPlaylist> createPlaylist({required String djUid, required String title}) async {
    final rows = await _supabase
        .from('dj_playlists')
        .insert({'dj_uid': djUid, 'title': title})
        .select('*')
        .limit(1);

    return DjPlaylist.fromRow((rows as List).first as Map<String, dynamic>);
  }

  Future<void> deletePlaylist({required String playlistId}) async {
    await _supabase.from('dj_playlists').delete().eq('id', playlistId);
  }

  Future<List<DjMessage>> listInbox({required String djUid, int limit = 50}) async {
    final rows = await _supabase
        .from('messages')
        .select('*')
        .eq('dj_uid', djUid)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DjMessage.fromRow)
        .toList();
  }

  Future<void> markMessageRead({required String messageId}) async {
    await _supabase
        .from('messages')
        .update({'is_read': true, 'read': true})
        .eq('id', messageId);
  }

  Future<List<DjBoost>> listBoosts({required String djUid, int limit = 50}) async {
    final rows = await _supabase
        .from('boosts')
        .select('*')
        .eq('dj_uid', djUid)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DjBoost.fromRow)
        .toList();
  }

  Future<DjBoost> createBoost({
    required String djUid,
    required String contentType,
    required String contentId,
    required num amount,
  }) async {
    final rows = await _supabase
        .from('boosts')
        .insert({
          'dj_uid': djUid,
          'content_type': contentType,
          'content_id': contentId,
          'amount': amount,
          'status': 'pending',
        })
        .select('*')
        .limit(1);

    return DjBoost.fromRow((rows as List).first as Map<String, dynamic>);
  }

  /// Schedules a live session/event in dj_events.
  Future<void> scheduleLive({
    required String djUid,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    await _supabase.from('dj_events').insert({
      'dj_id': djUid,
      'event_type': 'live',
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
      'status': 'scheduled',
      'metadata': {},
    });
  }

  Future<List<DjEvent>> listUpcomingLiveSchedule({
    required String djUid,
    int limit = 20,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _supabase
        .from('dj_events')
        .select('id,dj_id,event_type,title,description,starts_at,ends_at,status,metadata,created_at')
        .eq('dj_id', djUid)
        .inFilter('event_type', const ['live', 'dj_live', 'dj_live_session'])
        .gte('starts_at', now)
        .order('starts_at', ascending: true)
        .limit(limit);

    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(DjEvent.fromRow)
        .toList(growable: false);
  }

  Future<List<DjEvent>> listPastLiveSessions({
    required String djUid,
    int limit = 20,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _supabase
        .from('dj_events')
        .select('id,dj_id,event_type,title,description,starts_at,ends_at,status,metadata,created_at')
        .eq('dj_id', djUid)
        .inFilter('event_type', const ['live', 'dj_live', 'dj_live_session'])
        .lt('starts_at', now)
        .order('starts_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(DjEvent.fromRow)
        .toList(growable: false);
  }

  Future<num> bestEffortCoinsReceived({
    required String djUid,
    int limit = 2000,
  }) async {
    num sum = 0;

    // Sets/mixes coins.
    try {
      final rows = await _supabase
          .from('dj_sets')
          .select('coins_earned')
          .eq('dj_uid', djUid)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final v = r['coins_earned'];
        sum += (v is num) ? v : (num.tryParse((v ?? '0').toString()) ?? 0);
      }
    } catch (_) {
      // ignore
    }

    // Live sessions coins (view backed by dj_events metadata).
    try {
      final rows = await _supabase
          .from('dj_live_sessions')
          .select('coins_earned')
          .eq('dj_id', djUid)
          .limit(limit);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final v = r['coins_earned'];
        sum += (v is num) ? v : (num.tryParse((v ?? '0').toString()) ?? 0);
      }
    } catch (_) {
      // ignore
    }

    // Battles winnings coins.
    try {
      final rows = await _supabase
          .from('dj_battles')
          .select('coins_earned')
          .or('dj1_id.eq.$djUid,dj2_id.eq.$djUid')
          .limit(limit);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final v = r['coins_earned'];
        sum += (v is num) ? v : (num.tryParse((v ?? '0').toString()) ?? 0);
      }
    } catch (_) {
      // ignore
    }

    return sum;
  }

  /// Computes a best-effort genre specialty list from the DJ's latest sets.
  Future<List<String>> bestEffortGenreSpecialty({
    required String djUid,
    int setLimit = 200,
    int top = 3,
  }) async {
    try {
      final sets = await listSets(djUid: djUid, limit: setLimit);
      final counts = <String, int>{};
      for (final s in sets) {
        final g = (s.genre ?? '').trim();
        if (g.isEmpty) continue;
        counts[g] = (counts[g] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(top).map((e) => e.key).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<num> bestEffortTotalEarnings({required String djUid}) async {
    // Prefer Edge API wallet summary for the signed-in DJ.
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && currentUid.trim().isNotEmpty && currentUid.trim() == djUid.trim()) {
        final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
        return summary.totalEarned;
      }
    } catch (_) {
      // ignore
    }

    // Fallback: battles winnings (if available).
    try {
      final rows = await _supabase
          .from('battle_earnings')
          .select('amount')
          .eq('dj_id', djUid);
      final list = (rows as List<dynamic>);
      num sum = 0;
      for (final r in list.cast<Map<String, dynamic>>()) {
        final a = r['amount'];
        sum += (a is num) ? a : (num.tryParse((a ?? '0').toString()) ?? 0);
      }
      return sum;
    } catch (_) {
      // ignore
    }

    return 0;
  }

  Future<num> bestEffortCoinBalance({required String djUid}) async {
    // Prefer Edge API wallet summary for the signed-in DJ.
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && currentUid.trim().isNotEmpty && currentUid.trim() == djUid.trim()) {
        final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
        return summary.coinBalance;
      }
    } catch (_) {
      // ignore
    }

    // Fallback: sum coins from domain tables.
    try {
      return await bestEffortCoinsReceived(djUid: djUid, limit: 2000);
    } catch (_) {
      return 0;
    }
  }
}
