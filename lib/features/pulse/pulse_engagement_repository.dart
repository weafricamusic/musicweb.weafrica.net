import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/network/api_uri_builder.dart';
import '../../app/network/firebase_authed_http.dart';

class PulseComment {
  const PulseComment({
    required this.id,
    required this.videoId,
    required this.userId,
    required this.comment,
    required this.createdAt,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String videoId;
  final String userId;
  final String comment;
  final DateTime createdAt;

  final String? username;
  final String? displayName;
  final String? avatarUrl;
}

class PulseEngagementRepository {
  PulseEngagementRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  static const Duration _requestTimeout = Duration(seconds: 10);

  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  static bool _looksLikeUuid(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return _uuidRe.hasMatch(v);
  }

  static bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'on';
  }

  static bool _isMissingTableError(Object error) {
    final msg = error.toString().toLowerCase();
    // Postgres undefined_table
    if (msg.contains('42p01')) return true;
    if (msg.contains('undefined_table')) return true;
    if (msg.contains('does not exist') && msg.contains('relation')) return true;
    if (msg.contains('could not find the table')) return true;
    return false;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfilesByIds(
    Iterable<String> userIds,
  ) async {
    final ids = userIds
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};

    try {
      final rows = await _client
          .from('profiles')
          .select('id,username,display_name,avatar_url')
          .inFilter('id', ids)
          .limit(500);

      final out = <String, Map<String, dynamic>>{};
      for (final row in (rows as List<dynamic>).whereType<Map>()) {
        final m = row.map((k, v) => MapEntry(k.toString(), v));
        final id = (m['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        out[id] = m;
      }
      return out;
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  Future<Set<String>> listLikedVideoIds({required String userId}) async {
    try {
      final rows = await _client
          .from('video_likes')
          .select('video_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(500);

      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((r) => (r['video_id'] ?? '').toString())
          .where((id) => id.trim().isNotEmpty)
          .toSet();
    } catch (e) {
      if (!_isMissingTableError(e)) {
        // If the canonical table exists but RLS/permissions block, fall back
        // to legacy if possible.
      }
    }

    final rows = await _client
        .from('pulse_likes')
        .select('video_id')
        .eq('user_id', userId)
        .eq('liked', true)
        .order('updated_at', ascending: false)
        .limit(500);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((r) => (r['video_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<Set<String>> listFollowedArtistIds({required String userId}) async {
    final uid = userId.trim();
    if (uid.isEmpty) return <String>{};

    final out = <String>{};

    // Preferred canonical table for consumer -> artist follows.
    // Presence of a row means following.
    try {
      final rows = await _client
          .from('followers')
          .select('artist_id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(500);

      out.addAll(
        (rows as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map((r) => (r['artist_id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty),
      );
    } catch (_) {
      // Best-effort: table may not exist in older projects or RLS may block.
    }

    // Fallback/legacy table used by Pulse.
    try {
      final rows = await _client
          .from('pulse_follows')
          .select('artist_id,following')
          .eq('user_id', uid)
          .order('updated_at', ascending: false)
          .limit(500);

      for (final row in (rows as List<dynamic>).whereType<Map>()) {
        final m = row.map((k, v) => MapEntry(k.toString(), v));
        if (!_isTruthy(m['following'])) continue;
        final id = (m['artist_id'] ?? '').toString().trim();
        if (id.isNotEmpty) out.add(id);
      }
    } catch (_) {
      // ignore
    }

    return out;
  }

  Future<void> setLike({
    required String videoId,
    required String userId,
    required bool liked,
  }) async {
    final v = videoId.trim();
    final u = userId.trim();
    if (v.isEmpty || u.isEmpty) return;

    Object? lastError;
    var wrote = false;

    // Primary path: backend endpoint emit push and enforces server-side checks.
    try {
      final uri = _uriBuilder.build('/api/pulse/$v/like');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode(<String, Object?>{
          'liked': liked,
        }),
        timeout: _requestTimeout,
        requireAuth: true,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        wrote = true;
      } else {
        lastError = StateError('Like endpoint failed (${res.statusCode})');
      }
    } catch (e) {
      lastError = e;
    }

    if (wrote) return;

    // Canonical engagement table (presence of row == liked).
    try {
      if (liked) {
        await _client.from('video_likes').upsert(
          {
            'video_id': v,
            'user_id': u,
          },
          onConflict: 'video_id,user_id',
        );
      } else {
        await _client.from('video_likes').delete().eq('video_id', v).eq('user_id', u);
      }
      wrote = true;
    } catch (e) {
      lastError = e;
    }

    // Legacy Pulse table (liked boolean). Best-effort sync.
    try {
      await _client.from('pulse_likes').upsert({
        'video_id': v,
        'user_id': u,
        'liked': liked,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      wrote = true;
    } catch (e) {
      lastError ??= e;
    }

    if (!wrote && lastError != null) throw lastError;
  }

  Future<void> addComment({
    required String videoId,
    required String userId,
    required String comment,
  }) async {
    final trimmed = comment.trim();
    if (trimmed.isEmpty) return;

    try {
      await _client.from('video_comments').insert({
        'video_id': videoId,
        'user_id': userId,
        'comment': trimmed,
      });
      return;
    } catch (e) {
      if (!_isMissingTableError(e)) {
        // If blocked for a different reason, still try legacy.
      }
    }

    await _client.from('pulse_comments').insert({
      'video_id': videoId,
      'user_id': userId,
      'comment': trimmed,
    });
  }

  Future<List<PulseComment>> listComments({
    required String videoId,
    int limit = 50,
  }) async {
    final v = videoId.trim();
    if (v.isEmpty) return const <PulseComment>[];
    final cappedLimit = limit.clamp(1, 200);

    List<Map<String, dynamic>> rows;

    try {
      final raw = await _client
          .from('video_comments')
          .select('id,video_id,user_id,comment,created_at')
          .eq('video_id', v)
          .order('created_at', ascending: false)
          .limit(cappedLimit);
      rows = (raw as List<dynamic>)
          .whereType<Map>()
          .map((m) => m.map((k, val) => MapEntry(k.toString(), val)))
          .toList(growable: false);
    } catch (e) {
      if (!_isMissingTableError(e)) {
        // fall through and try legacy
      }
      final raw = await _client
          .from('pulse_comments')
          .select('id,video_id,user_id,comment,created_at')
          .eq('video_id', v)
          .limit(cappedLimit);
      rows = (raw as List<dynamic>)
          .whereType<Map>()
          .map((m) => m.map((k, val) => MapEntry(k.toString(), val)))
          .toList(growable: false);
      rows.sort((a, b) {
        final da = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
    }

    final profileById = await _loadProfilesByIds(
      rows.map((r) => (r['user_id'] ?? '').toString()),
    );

    return rows.map((r) {
      final id = (r['id'] ?? '').toString();
      final uid = (r['user_id'] ?? '').toString();
      final profile = profileById[uid];
      final created = DateTime.tryParse('${r['created_at'] ?? ''}') ?? DateTime.now().toUtc();
      return PulseComment(
        id: id.trim().isEmpty ? '${v}_$uid${created.millisecondsSinceEpoch}' : id,
        videoId: (r['video_id'] ?? v).toString(),
        userId: uid,
        comment: (r['comment'] ?? '').toString(),
        createdAt: created,
        username: (profile?['username'] ?? '').toString().trim().isEmpty
            ? null
            : (profile?['username'] ?? '').toString().trim(),
        displayName: (profile?['display_name'] ?? '').toString().trim().isEmpty
            ? null
            : (profile?['display_name'] ?? '').toString().trim(),
        avatarUrl: (profile?['avatar_url'] ?? '').toString().trim().isEmpty
            ? null
            : (profile?['avatar_url'] ?? '').toString().trim(),
      );
    }).toList(growable: false);
  }

  Future<void> recordShare({required String videoId, required String userId}) async {
    final v = videoId.trim();
    final u = userId.trim();
    if (v.isEmpty || u.isEmpty) return;
    await _client.from('video_shares').insert({
      'video_id': v,
      'user_id': u,
    });
  }

  Future<Set<String>> listSavedVideoIds({required String userId}) async {
    final rows = await _client
        .from('video_saves')
        .select('video_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((r) => (r['video_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<void> setSaved({
    required String videoId,
    required String userId,
    required bool saved,
  }) async {
    final v = videoId.trim();
    final u = userId.trim();
    if (v.isEmpty || u.isEmpty) return;
    if (saved) {
      await _client.from('video_saves').upsert(
        {'video_id': v, 'user_id': u},
        onConflict: 'video_id,user_id',
      );
    } else {
      await _client.from('video_saves').delete().eq('video_id', v).eq('user_id', u);
    }
  }

  Future<Set<String>> listNotInterestedVideoIds({required String userId}) async {
    final rows = await _client
        .from('video_not_interested')
        .select('video_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((r) => (r['video_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<void> setNotInterested({
    required String videoId,
    required String userId,
    required bool notInterested,
  }) async {
    final v = videoId.trim();
    final u = userId.trim();
    if (v.isEmpty || u.isEmpty) return;
    if (notInterested) {
      await _client.from('video_not_interested').upsert(
        {'video_id': v, 'user_id': u},
        onConflict: 'video_id,user_id',
      );
    } else {
      await _client
          .from('video_not_interested')
          .delete()
          .eq('video_id', v)
          .eq('user_id', u);
    }
  }

  Future<void> reportVideo({
    required String videoId,
    required String reason,
    required String reporterId,
  }) async {
    final v = videoId.trim();
    final r = _normalizeReportReason(reason);
    final uid = reporterId.trim();
    if (v.isEmpty || r.isEmpty || uid.isEmpty) return;
    await _client.from('reports').insert({
      'content_type': 'video',
      'content_id': v,
      'reason': r,
      'reporter_id': uid,
    });
  }

  String _normalizeReportReason(String raw) {
    final reason = raw.trim();
    if (reason.isEmpty) return '';

    const allowed = <String>{
      'copyright_infringement',
      'nudity_sexual_content',
      'hate_violence',
      'spam_scam',
      'harassment',
      'fake_account',
      'other',
    };
    if (allowed.contains(reason)) return reason;

    switch (reason.toLowerCase()) {
      case 'spam':
      case 'spam or scam':
        return 'spam_scam';
      case 'nudity':
      case 'nudity or sexual content':
        return 'nudity_sexual_content';
      case 'violence':
      case 'hate speech':
      case 'hate or violence':
        return 'hate_violence';
      case 'copyright':
      case 'copyright infringement':
        return 'copyright_infringement';
      case 'harassment':
        return 'harassment';
      case 'impersonation':
      case 'fake account':
        return 'fake_account';
      default:
        return 'other';
    }
  }

  Future<void> setFollow({
    required String artistId,
    required String userId,
    required bool following,
  }) async {
    final a = artistId.trim();
    final u = userId.trim();
    if (a.isEmpty || u.isEmpty) return;

    Object? lastError;
    var wrote = false;

    // If the artist id looks like a UUID, keep the canonical `followers` table
    // in sync (admin tooling typically writes here).
    if (_looksLikeUuid(a)) {
      try {
        if (following) {
          await _client.from('followers').upsert(
            {
              'artist_id': a,
              'user_id': u,
            },
            onConflict: 'artist_id,user_id',
          );
        } else {
          await _client.from('followers').delete().eq('artist_id', a).eq('user_id', u);
        }
        wrote = true;
      } catch (e) {
        lastError = e;
      }
    }

    // Keep the Pulse table in sync if it exists.
    try {
      await _client.from('pulse_follows').upsert({
        'artist_id': a,
        'user_id': u,
        'following': following,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      wrote = true;
    } catch (e) {
      lastError ??= e;
    }

    if (!wrote && lastError != null) {
      throw lastError;
    }
  }

  /// Sends a gift using the backend wallet + gifts pipeline.
  ///
  /// This reuses the `send_gift` RPC introduced for Live Battles. For Pulse,
  /// pass a per-video `channelId` (e.g. `pulse:<videoId>`).
  Future<int> sendGift({
    required String channelId,
    required String fromUserId,
    required String toHostId,
    required String giftId,
    required int coinCost,
    required String senderName,
  }) async {
    try {
      final res = await _client.rpc(
        'send_gift',
        params: {
          'p_channel_id': channelId,
          'p_from_user_id': fromUserId,
          'p_to_host_id': toHostId,
          'p_gift_id': giftId,
          'p_coin_cost': coinCost,
          'p_sender_name': senderName,
        },
      );

      // Supabase may return a list of rows for table-returning functions.
      if (res is List && res.isNotEmpty && res.first is Map) {
        final m = (res.first as Map).cast<String, dynamic>();
        final balRaw = m['new_balance'] ?? m['newBalance'];
        final bal = balRaw is num ? balRaw.toInt() : int.tryParse('$balRaw');
        if (bal != null) return bal;
      }

      // Some clients return a single map.
      if (res is Map) {
        final m = res.cast<String, dynamic>();
        final balRaw = m['new_balance'] ?? m['newBalance'];
        final bal = balRaw is num ? balRaw.toInt() : int.tryParse('$balRaw');
        if (bal != null) return bal;
      }

      throw StateError('Gift response invalid');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('insufficient_balance')) {
        throw StateError('Not enough coins.');
      }
      if (msg.contains('permission') || msg.contains('not allowed') || msg.contains('denied')) {
        throw StateError('Gifting is not enabled on this project yet.');
      }
      if (msg.contains("send_gift") && msg.contains('not found')) {
        throw StateError('Gift backend not installed.');
      }
      rethrow;
    }
  }
}
