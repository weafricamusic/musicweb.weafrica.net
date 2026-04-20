import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/artist_fan_club_models.dart';
import 'artist_identity_service.dart';

class ArtistFanClubService {
  ArtistFanClubService({
    SupabaseClient? client,
    ArtistIdentityService? identity,
    FirebaseAuth? auth,
  })  : _client = client ?? Supabase.instance.client,
        _identity = identity ?? ArtistIdentityService(client: client ?? Supabase.instance.client),
        _auth = auth ?? FirebaseAuth.instance;

  final SupabaseClient _client;
  final ArtistIdentityService _identity;
  final FirebaseAuth _auth;

  String _requireUid() {
    final uid = _auth.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      throw StateError('Not signed in');
    }
    return uid;
  }

  Future<FanClubHubData> loadHub() async {
    final artistUid = _requireUid();
    final artistId = await _identity.resolveArtistIdForCurrentUser();

    await _ensureDefaultTiers(artistUid: artistUid);

    final results = await Future.wait<dynamic>([
      _loadArtistMeta(artistId: artistId, artistUid: artistUid),
      _loadFollowers(artistId: artistId),
      _loadMemberships(artistUid: artistUid),
      _loadTiers(artistUid: artistUid),
      _loadContent(artistUid: artistUid),
      _loadAnnouncements(artistUid: artistUid),
      _loadRewards(artistUid: artistUid),
      _loadClubEarningsMwk(artistUid: artistUid),
      _loadEngagement(artistUid: artistUid),
    ]);

    final meta = results[0] as Map<String, String>;
    final followerIds = results[1] as List<_FollowerRef>;
    final memberships = results[2] as Map<String, _MembershipRef>;
    final tiers = results[3] as List<FanClubTier>;
    final content = results[4] as List<FanClubContentItem>;
    final announcements = results[5] as List<FanClubAnnouncementItem>;
    final rewards = results[6] as List<FanClubRewardItem>;
    final clubEarnings = results[7] as double;
    final engagement = results[8] as _EngagementRef;

    final fans = await _assembleFans(
      followerRefs: followerIds,
      memberships: memberships,
      artistId: artistId,
      artistUid: artistUid,
    );

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final prevMonthStart = DateTime(now.year, now.month - 1);

    int membersThisMonth = 0;
    int membersLastMonth = 0;
    int vipThisMonth = 0;
    int followerThisMonth = 0;
    int followerLastMonth = 0;

    for (final membership in memberships.values) {
      final joined = membership.joinedAt;
      if (joined == null) continue;
      if (joined.isAfter(monthStart) || joined.isAtSameMomentAs(monthStart)) {
        membersThisMonth += 1;
        if (membership.tierKey == 'vip') vipThisMonth += 1;
      } else if (joined.isAfter(prevMonthStart) || joined.isAtSameMomentAs(prevMonthStart)) {
        membersLastMonth += 1;
      }
    }

    for (final follower in followerIds) {
      final joined = follower.createdAt;
      if (joined == null) continue;
      if (joined.isAfter(monthStart) || joined.isAtSameMomentAs(monthStart)) {
        followerThisMonth += 1;
      } else if (joined.isAfter(prevMonthStart) || joined.isAtSameMomentAs(prevMonthStart)) {
        followerLastMonth += 1;
      }
    }

    final topGifters = [...fans]..sort((a, b) => b.giftsSent.compareTo(a.giftsSent));
    final topSpenders = [...fans]..sort((a, b) => b.totalSpentMwk.compareTo(a.totalSpentMwk));
    final vipMembersCount = fans.where((f) => f.tierKey == 'vip').length;
    final ratedFans = fans.where((fan) => fan.totalSpentMwk > 0 || fan.comments > 0 || fan.giftsSent > 0).length;
    final averageRating = ratedFans == 0 ? 4.8 : (4.2 + (ratedFans.clamp(0, 30) / 50));

    return FanClubHubData(
      artistGenre: meta['genre'] ?? 'Artist',
      artistCountry: meta['country'] ?? 'Malawi',
      fansCount: fans.length,
      followersCount: followerIds.length,
      clubEarningsMwk: clubEarnings,
      vipMembersCount: vipMembersCount,
      membersGrowthThisMonth: membersThisMonth - membersLastMonth,
      followersGrowthThisMonth: followerThisMonth - followerLastMonth,
      vipGrowthThisMonth: vipThisMonth,
      averageRating: double.parse(averageRating.toStringAsFixed(1)),
      tiers: tiers,
      fans: fans,
      contentItems: content,
      announcements: announcements,
      rewards: rewards,
      analytics: FanClubAnalytics(
        growthDelta: membersThisMonth - membersLastMonth,
        topGifters: topGifters.take(3).toList(growable: false),
        topSpenders: topSpenders.take(3).toList(growable: false),
        commentsCount: engagement.comments,
        likesCount: engagement.likes,
        sharesCount: engagement.shares,
      ),
    );
  }

  Future<void> updateTier(FanClubTier tier) async {
    final artistUid = _requireUid();
    await _client.from('fan_club_tiers').upsert(
      tier.toUpsertRow(artistUid: artistUid),
      onConflict: 'artist_uid,tier_key',
    );
  }

  Future<void> setFanTier({
    required String fanUserId,
    required String tierKey,
    required FanClubFan current,
  }) async {
    final artistUid = _requireUid();
    await _client.from('fan_club_memberships').upsert({
      'artist_uid': artistUid,
      'fan_user_id': fanUserId,
      'tier_key': tierKey,
      'status': 'active',
      'joined_at': current.joinedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'total_spent_mwk': current.totalSpentMwk,
      'gifts_sent_count': current.giftsSent,
      'comments_count': current.comments,
    }, onConflict: 'artist_uid,fan_user_id');
  }

  Future<void> createOrUpdateContent({
    String? id,
    required String title,
    required String description,
    required String contentType,
    required String accessTier,
    String? mediaUrl,
  }) async {
    final artistUid = _requireUid();
    final payload = {
      'artist_uid': artistUid,
      'title': title,
      'description': description,
      'content_type': contentType,
      'access_tier': accessTier,
      'media_url': (mediaUrl ?? '').trim().isEmpty ? null : mediaUrl!.trim(),
      'published_at': DateTime.now().toIso8601String(),
    };

    if ((id ?? '').trim().isEmpty) {
      await _client.from('fan_club_content').insert(payload);
      return;
    }

    await _client.from('fan_club_content').update(payload).eq('id', id!.trim()).eq('artist_uid', artistUid);
  }

  Future<void> deleteContent(String id) async {
    final artistUid = _requireUid();
    await _client.from('fan_club_content').delete().eq('id', id).eq('artist_uid', artistUid);
  }

  Future<void> sendAnnouncement({
    required String audience,
    required String message,
    String? linkUrl,
    String? imageUrl,
  }) async {
    final artistUid = _requireUid();
    await _client.from('fan_club_announcements').insert({
      'artist_uid': artistUid,
      'audience': audience,
      'message': message,
      'link_url': (linkUrl ?? '').trim().isEmpty ? null : linkUrl!.trim(),
      'image_url': (imageUrl ?? '').trim().isEmpty ? null : imageUrl!.trim(),
      'status': 'sent',
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> sendReward({
    required String rewardType,
    required String audience,
    required String note,
    required List<String> recipientIds,
  }) async {
    final artistUid = _requireUid();
    await _client.from('fan_club_rewards').insert({
      'artist_uid': artistUid,
      'reward_type': rewardType,
      'audience': audience,
      'note': note,
      'recipients': recipientIds,
      'recipients_count': recipientIds.length,
    });
  }

  Future<void> _ensureDefaultTiers({required String artistUid}) async {
    final defaults = _defaultTiers();

    try {
      for (final tier in defaults) {
        await _client.from('fan_club_tiers').upsert(
          tier.toUpsertRow(artistUid: artistUid),
          onConflict: 'artist_uid,tier_key',
        );
      }
    } catch (e) {
      developer.log('ArtistFanClubService _ensureDefaultTiers failed: $e', name: 'WEAFRICA.FanClub');
    }
  }

  List<FanClubTier> _defaultTiers() {
    return const <FanClubTier>[
      FanClubTier(
        id: '',
        tierKey: 'free',
        title: 'FREE',
        priceMwk: 0,
        description: 'Follow artist',
        perks: <String>['Follow artist', 'Public posts', 'Comment on public posts'],
        badgeLabel: 'FREE',
        accentColor: '#7A7A7A',
        isActive: true,
        memberCount: 0,
      ),
      FanClubTier(
        id: '',
        tierKey: 'premium',
        title: 'PREMIUM',
        priceMwk: 2500,
        description: 'Exclusive content and early access',
        perks: <String>['Exclusive content', 'Early access to songs', 'Member-only live streams', 'Badge in comments', '10% off merch'],
        badgeLabel: 'PREMIUM',
        accentColor: '#E6B800',
        isActive: true,
        memberCount: 0,
      ),
      FanClubTier(
        id: '',
        tierKey: 'vip',
        title: 'VIP',
        priceMwk: 10000,
        description: 'Direct access and top-tier perks',
        perks: <String>['All Premium benefit', 'Private WhatsApp group', 'Monthly video call', 'Personalized shoutout', 'Name in credit', 'Exclusive merch'],
        badgeLabel: 'VIP',
        accentColor: '#D4AF37',
        isActive: true,
        memberCount: 0,
      ),
    ];
  }

  Future<Map<String, String>> _loadArtistMeta({required String? artistId, required String artistUid}) async {
    final meta = <String, String>{};
    try {
      List<dynamic> rows = const <dynamic>[];
      if ((artistId ?? '').trim().isNotEmpty) {
        rows = await _client
            .from('artists')
            .select('genre,country')
            .eq('id', artistId!)
            .limit(1);
      }
      if (rows.isEmpty) {
        rows = await _client.from('artists').select('genre,country').or('user_id.eq.$artistUid,firebase_uid.eq.$artistUid').limit(1);
      }
      if (rows.isNotEmpty && rows.first is Map) {
        final row = (rows.first as Map).map((k, v) => MapEntry(k.toString(), v));
        final genre = (row['genre'] ?? '').toString().trim();
        final country = (row['country'] ?? '').toString().trim();
        if (genre.isNotEmpty) meta['genre'] = genre;
        if (country.isNotEmpty) meta['country'] = country;
      }
    } catch (e) {
      developer.log('ArtistFanClubService _loadArtistMeta failed: $e', name: 'WEAFRICA.FanClub');
    }
    return meta;
  }

  Future<List<FanClubTier>> _loadTiers({required String artistUid}) async {
    try {
      final rows = await _client.from('fan_club_tiers').select('*').eq('artist_uid', artistUid).order('price_mwk');
      final tiers = (rows as List<dynamic>).whereType<Map<String, dynamic>>().map(FanClubTier.fromRow).toList(growable: false);
      return tiers.isEmpty ? _defaultTiers() : tiers;
    } catch (e) {
      developer.log('ArtistFanClubService _loadTiers failed: $e', name: 'WEAFRICA.FanClub');
      return _defaultTiers();
    }
  }

  Future<List<_FollowerRef>> _loadFollowers({required String? artistId}) async {
    final id = (artistId ?? '').trim();
    if (id.isEmpty) return const <_FollowerRef>[];

    try {
      final rows = await _client.from('followers').select('user_id,created_at').eq('artist_id', id).order('created_at', ascending: false).limit(500);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().map((row) {
        return _FollowerRef(
          userId: (row['user_id'] ?? '').toString(),
          createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
        );
      }).where((row) => row.userId.trim().isNotEmpty).toList(growable: false);
    } catch (e) {
      developer.log('ArtistFanClubService _loadFollowers failed: $e', name: 'WEAFRICA.FanClub');
      return const <_FollowerRef>[];
    }
  }

  Future<Map<String, _MembershipRef>> _loadMemberships({required String artistUid}) async {
    try {
      final rows = await _client.from('fan_club_memberships').select('*').eq('artist_uid', artistUid).order('updated_at', ascending: false).limit(500);
      final out = <String, _MembershipRef>{};
      for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
        final userId = (row['fan_user_id'] ?? '').toString().trim();
        if (userId.isEmpty) continue;
        out[userId] = _MembershipRef(
          tierKey: (row['tier_key'] ?? 'free').toString(),
          joinedAt: DateTime.tryParse((row['joined_at'] ?? '').toString()),
          totalSpentMwk: readDouble(row['total_spent_mwk']),
          giftsSent: _readInt(row['gifts_sent_count']),
          comments: _readInt(row['comments_count']),
        );
      }
      return out;
    } catch (e) {
      developer.log('ArtistFanClubService _loadMemberships failed: $e', name: 'WEAFRICA.FanClub');
      return const <String, _MembershipRef>{};
    }
  }

  Future<List<FanClubContentItem>> _loadContent({required String artistUid}) async {
    try {
      final rows = await _client.from('fan_club_content').select('*').eq('artist_uid', artistUid).order('published_at', ascending: false).limit(50);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().map(FanClubContentItem.fromRow).toList(growable: false);
    } catch (e) {
      developer.log('ArtistFanClubService _loadContent failed: $e', name: 'WEAFRICA.FanClub');
      return const <FanClubContentItem>[];
    }
  }

  Future<List<FanClubAnnouncementItem>> _loadAnnouncements({required String artistUid}) async {
    try {
      final rows = await _client.from('fan_club_announcements').select('*').eq('artist_uid', artistUid).order('created_at', ascending: false).limit(25);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().map(FanClubAnnouncementItem.fromRow).toList(growable: false);
    } catch (e) {
      developer.log('ArtistFanClubService _loadAnnouncements failed: $e', name: 'WEAFRICA.FanClub');
      return const <FanClubAnnouncementItem>[];
    }
  }

  Future<List<FanClubRewardItem>> _loadRewards({required String artistUid}) async {
    try {
      final rows = await _client.from('fan_club_rewards').select('*').eq('artist_uid', artistUid).order('created_at', ascending: false).limit(25);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().map(FanClubRewardItem.fromRow).toList(growable: false);
    } catch (e) {
      developer.log('ArtistFanClubService _loadRewards failed: $e', name: 'WEAFRICA.FanClub');
      return const <FanClubRewardItem>[];
    }
  }

  Future<double> _loadClubEarningsMwk({required String artistUid}) async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month).toIso8601String();
      final rows = await _client
          .from('wallet_transactions')
          .select('amount,balance_type,type,created_at')
          .eq('user_id', artistUid)
          .eq('balance_type', 'cash')
          .gte('created_at', monthStart)
          .limit(500);

      double sum = 0;
      for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
        sum += readDouble(row['amount']);
      }
      return sum;
    } catch (e) {
      developer.log('ArtistFanClubService _loadClubEarningsMwk failed: $e', name: 'WEAFRICA.FanClub');
      return 0;
    }
  }

  Future<_EngagementRef> _loadEngagement({required String artistUid}) async {
    try {
      final songIds = await _loadSongIds(artistUid: artistUid);
      final videoIds = await _loadVideoIds(artistUid: artistUid);

      int comments = 0;
      int likes = 0;

      if (songIds.isNotEmpty) {
        try {
          final rows = await _client.from('song_comments').select('id').inFilter('song_id', songIds).limit(1000);
          comments += (rows as List<dynamic>).length;
        } catch (_) {}
      }

      if (videoIds.isNotEmpty) {
        try {
          final rows = await _client.from('video_comments').select('id').inFilter('video_id', videoIds).limit(1000);
          comments += (rows as List<dynamic>).length;
        } catch (_) {}
        try {
          final rows = await _client.from('video_likes').select('id').inFilter('video_id', videoIds).limit(1000);
          likes += (rows as List<dynamic>).length;
        } catch (_) {}
      }

      return _EngagementRef(comments: comments, likes: likes, shares: 0);
    } catch (e) {
      developer.log('ArtistFanClubService _loadEngagement failed: $e', name: 'WEAFRICA.FanClub');
      return const _EngagementRef(comments: 0, likes: 0, shares: 0);
    }
  }

  Future<List<String>> _loadSongIds({required String artistUid}) async {
    try {
      final rows = await _client.from('songs').select('id').or('artist.eq.$artistUid,user_id.eq.$artistUid').limit(500);
      return (rows as List<dynamic>)
          .whereType<Map>()
          .map((row) => (row['id'] ?? '').toString())
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<String>> _loadVideoIds({required String artistUid}) async {
    try {
      final rows = await _client.from('videos').select('id').or('artist_id.eq.$artistUid,user_id.eq.$artistUid,artist_uid.eq.$artistUid').limit(500);
      return (rows as List<dynamic>)
          .whereType<Map>()
          .map((row) => (row['id'] ?? '').toString())
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<FanClubFan>> _assembleFans({
    required List<_FollowerRef> followerRefs,
    required Map<String, _MembershipRef> memberships,
    required String? artistId,
    required String artistUid,
  }) async {
    final userIds = followerRefs.map((row) => row.userId).toSet().toList(growable: false);
    final namesById = <String, String>{};
    final avatarById = <String, String?>{};

    if (userIds.isNotEmpty) {
      try {
        final profileRows = await _client.from('profiles').select('id,username,display_name,full_name,avatar_url').inFilter('id', userIds);
        for (final row in (profileRows as List<dynamic>).whereType<Map<String, dynamic>>()) {
          final id = (row['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final name = (row['display_name'] ?? row['full_name'] ?? row['username'] ?? 'Fan').toString().trim();
          namesById[id] = name.isEmpty ? 'Fan' : name;
          final avatar = (row['avatar_url'] ?? '').toString().trim();
          avatarById[id] = avatar.isEmpty ? null : avatar;
        }
      } catch (e) {
        developer.log('ArtistFanClubService _assembleFans profiles failed: $e', name: 'WEAFRICA.FanClub');
      }
    }

    final spending = await _loadSpendingByFan(artistId: artistId, artistUid: artistUid, userIds: userIds);

    final fans = <FanClubFan>[];
    for (final follower in followerRefs) {
      final membership = memberships[follower.userId];
      fans.add(
        FanClubFan(
          userId: follower.userId,
          displayName: namesById[follower.userId] ?? 'Fan ${follower.userId.substring(0, follower.userId.length.clamp(0, 6))}',
          avatarUrl: avatarById[follower.userId],
          tierKey: membership?.tierKey ?? 'free',
          joinedAt: membership?.joinedAt ?? follower.createdAt,
          totalSpentMwk: membership?.totalSpentMwk ?? spending[follower.userId] ?? 0,
          giftsSent: membership?.giftsSent ?? 0,
          comments: membership?.comments ?? 0,
        ),
      );
    }
    return fans;
  }

  Future<Map<String, double>> _loadSpendingByFan({
    required String? artistId,
    required String artistUid,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return const <String, double>{};

    try {
      dynamic query = _client.from('transactions').select('actor_id,target_id,target_type,amount_mwk,type').eq('target_type', 'artist').inFilter('actor_id', userIds).limit(1000);
      if ((artistId ?? '').trim().isNotEmpty) {
        query = query.eq('target_id', artistId!);
      } else {
        query = query.eq('target_id', artistUid);
      }
      final rows = await query;
      final out = <String, double>{};
      for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
        final actorId = (row['actor_id'] ?? '').toString().trim();
        if (actorId.isEmpty) continue;
        out[actorId] = (out[actorId] ?? 0) + readDouble(row['amount_mwk']);
      }
      return out;
    } catch (_) {
      return const <String, double>{};
    }
  }
}

class _FollowerRef {
  const _FollowerRef({required this.userId, required this.createdAt});

  final String userId;
  final DateTime? createdAt;
}

class _MembershipRef {
  const _MembershipRef({
    required this.tierKey,
    required this.joinedAt,
    required this.totalSpentMwk,
    required this.giftsSent,
    required this.comments,
  });

  final String tierKey;
  final DateTime? joinedAt;
  final double totalSpentMwk;
  final int giftsSent;
  final int comments;
}

class _EngagementRef {
  const _EngagementRef({
    required this.comments,
    required this.likes,
    required this.shares,
  });

  final int comments;
  final int likes;
  final int shares;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}