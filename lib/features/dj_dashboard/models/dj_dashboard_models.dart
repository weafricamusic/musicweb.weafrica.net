class DjProfile {
  final String djUid;
  final String? stageName;
  final String? country;
  final String? bio;
  final String? profilePhoto;
  final int followersCount;
  final String? bankAccount;
  final String? mobileMoneyPhone;

  const DjProfile({
    required this.djUid,
    required this.stageName,
    required this.country,
    required this.bio,
    required this.profilePhoto,
    required this.followersCount,
    this.bankAccount,
    this.mobileMoneyPhone,
  });

  factory DjProfile.fromRow(Map<String, dynamic> row) {
    return DjProfile(
      djUid: (row['dj_uid'] ?? '').toString(),
      stageName: row['stage_name']?.toString(),
      country: row['country']?.toString(),
      bio: row['bio']?.toString(),
      profilePhoto: row['profile_photo']?.toString(),
      followersCount: (row['followers_count'] is num)
          ? (row['followers_count'] as num).toInt()
          : int.tryParse((row['followers_count'] ?? '0').toString()) ?? 0,
      bankAccount: row['bank_account']?.toString(),
      mobileMoneyPhone: row['mobile_money_phone']?.toString(),
    );
  }

  Map<String, dynamic> toUpsertRow() {
    return {
      'dj_uid': djUid,
      'stage_name': stageName,
      'country': country,
      'bio': bio,
      'profile_photo': profilePhoto,
      'bank_account': bankAccount,
      'mobile_money_phone': mobileMoneyPhone,
    };
  }
}

class DjSet {
  final String id;
  final String djUid;
  final String title;
  final String? genre;
  final int? duration;
  final String audioUrl;
  final int plays;
  final int likes;
  final int comments;
  final int coinsEarned;
  final DateTime createdAt;

  const DjSet({
    required this.id,
    required this.djUid,
    required this.title,
    required this.genre,
    required this.duration,
    required this.audioUrl,
    required this.plays,
    required this.likes,
    required this.comments,
    required this.coinsEarned,
    required this.createdAt,
  });

  factory DjSet.fromRow(Map<String, dynamic> row) {
    return DjSet(
      id: (row['id'] ?? '').toString(),
      djUid: (row['dj_uid'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      genre: row['genre']?.toString(),
      duration: (row['duration'] is num)
          ? (row['duration'] as num).toInt()
          : int.tryParse((row['duration'] ?? '').toString()),
      audioUrl: (row['audio_url'] ?? '').toString(),
      plays: (row['plays'] is num)
          ? (row['plays'] as num).toInt()
          : int.tryParse((row['plays'] ?? '0').toString()) ?? 0,
      likes: (row['likes'] is num)
          ? (row['likes'] as num).toInt()
          : int.tryParse((row['likes'] ?? '0').toString()) ?? 0,
      comments: (row['comments'] is num)
          ? (row['comments'] as num).toInt()
          : int.tryParse((row['comments'] ?? '0').toString()) ?? 0,
      coinsEarned: (row['coins_earned'] is num)
          ? (row['coins_earned'] as num).toInt()
          : int.tryParse((row['coins_earned'] ?? '0').toString()) ?? 0,
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DjPlaylist {
  final String id;
  final String djUid;
  final String title;
  final DateTime createdAt;

  const DjPlaylist({
    required this.id,
    required this.djUid,
    required this.title,
    required this.createdAt,
  });

  factory DjPlaylist.fromRow(Map<String, dynamic> row) {
    return DjPlaylist(
      id: (row['id'] ?? '').toString(),
      djUid: (row['dj_uid'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DjMessage {
  final String id;
  final String djUid;
  final String? senderName;
  final String? senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  const DjMessage({
    required this.id,
    required this.djUid,
    required this.senderName,
    required this.senderId,
    required this.content,
    required this.isRead,
    required this.createdAt,
  });

  factory DjMessage.fromRow(Map<String, dynamic> row) {
    final dynamic readRaw = row['is_read'] ?? row['read'];
    final bool isRead = readRaw is bool
        ? readRaw
        : (readRaw?.toString().toLowerCase() == 'true');

    final content = (row['content'] ?? row['message'] ?? row['body'] ?? '').toString();

    return DjMessage(
      id: (row['id'] ?? '').toString(),
      djUid: (row['dj_uid'] ?? '').toString(),
      senderName: row['sender_name']?.toString(),
      senderId: row['sender_id']?.toString(),
      content: content,
      isRead: isRead,
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DjBoost {
  final String id;
  final String djUid;
  final String? contentId;
  final String? contentType;
  final num amount;
  final String status;
  final DateTime createdAt;

  const DjBoost({
    required this.id,
    required this.djUid,
    required this.contentId,
    required this.contentType,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory DjBoost.fromRow(Map<String, dynamic> row) {
    return DjBoost(
      id: (row['id'] ?? '').toString(),
      djUid: (row['dj_uid'] ?? '').toString(),
      contentId: row['content_id']?.toString(),
      contentType: row['content_type']?.toString(),
      amount: (row['amount'] is num)
          ? (row['amount'] as num)
          : num.tryParse((row['amount'] ?? '0').toString()) ?? 0,
      status: (row['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DjEvent {
  final String id;
  final String djId;
  final String eventType;
  final String? title;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const DjEvent({
    required this.id,
    required this.djId,
    required this.eventType,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.metadata,
    required this.createdAt,
  });

  factory DjEvent.fromRow(Map<String, dynamic> row) {
    final meta = row['metadata'];
    return DjEvent(
      id: (row['id'] ?? '').toString(),
      djId: (row['dj_id'] ?? row['djUid'] ?? '').toString(),
      eventType: (row['event_type'] ?? row['eventType'] ?? 'generic').toString(),
      title: row['title']?.toString(),
      description: row['description']?.toString(),
      startsAt: row['starts_at'] == null
          ? null
          : DateTime.tryParse(row['starts_at'].toString()),
      endsAt: row['ends_at'] == null
          ? null
          : DateTime.tryParse(row['ends_at'].toString()),
      status: (row['status'] ?? 'scheduled').toString(),
      metadata: (meta is Map)
          ? meta.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String? get replayUrl {
    final raw = (metadata['replay_url'] ?? metadata['replayUrl'] ?? metadata['replay']).toString();
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    return trimmed;
  }
}

class DjDashboardHomeData {
  final int totalPlays;
  final int followersCount;
  final num totalEarnings;
  final num coinBalance;
  final int setsCount;
  final int unreadMessagesCount;
  final int boostsCount;
  final List<DjSet> recentSets;
  final List<DjEvent> upcomingLives;
  final List<DjMessage> recentInbox;

  const DjDashboardHomeData({
    required this.totalPlays,
    required this.followersCount,
    required this.totalEarnings,
    required this.coinBalance,
    required this.setsCount,
    required this.unreadMessagesCount,
    required this.boostsCount,
    required this.recentSets,
    required this.upcomingLives,
    required this.recentInbox,
  });
}
