/// Represents a live streaming session.
class LiveStream {
  final String id;
  final String hostId;
  final String hostName;
  final String? hostAvatar;
  final String title;
  final String? description;
  final int viewerCount;
  final DateTime startedAt;
  final bool isLive;

  LiveStream({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.hostAvatar,
    required this.title,
    this.description,
    this.viewerCount = 0,
    required this.startedAt,
    this.isLive = true,
  });

  factory LiveStream.fromJson(Map<String, dynamic> json) {
    return LiveStream(
      id: json['id'] as String,
      hostId: json['host_id'] as String,
      hostName: json['host_name'] as String,
      hostAvatar: json['host_avatar'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      viewerCount: json['viewer_count'] as int? ?? 0,
      startedAt: DateTime.parse(json['started_at'] as String),
      isLive: json['is_live'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'host_id': hostId,
      'host_name': hostName,
      'host_avatar': hostAvatar,
      'title': title,
      'description': description,
      'viewer_count': viewerCount,
      'started_at': startedAt.toIso8601String(),
      'is_live': isLive,
    };
  }
}

/// Represents a live battle between two artists.
class LiveBattle {
  final String id;
  final String challengerId;
  final String challengerName;
  final String? challengerAvatar;
  final String opponentId;
  final String opponentName;
  final String? opponentAvatar;
  final DateTime startedAt;
  final int durationSeconds;
  final String status; // 'pending', 'active', 'completed'

  LiveBattle({
    required this.id,
    required this.challengerId,
    required this.challengerName,
    this.challengerAvatar,
    required this.opponentId,
    required this.opponentName,
    this.opponentAvatar,
    required this.startedAt,
    this.durationSeconds = 180, // Default 3 minutes
    this.status = 'pending',
  });

  factory LiveBattle.fromJson(Map<String, dynamic> json) {
    return LiveBattle(
      id: json['id'] as String,
      challengerId: json['challenger_id'] as String,
      challengerName: json['challenger_name'] as String,
      challengerAvatar: json['challenger_avatar'] as String?,
      opponentId: json['opponent_id'] as String,
      opponentName: json['opponent_name'] as String,
      opponentAvatar: json['opponent_avatar'] as String?,
      startedAt: DateTime.parse(json['started_at'] as String),
      durationSeconds: json['duration_seconds'] as int? ?? 180,
      status: json['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challenger_id': challengerId,
      'challenger_name': challengerName,
      'challenger_avatar': challengerAvatar,
      'opponent_id': opponentId,
      'opponent_name': opponentName,
      'opponent_avatar': opponentAvatar,
      'started_at': startedAt.toIso8601String(),
      'duration_seconds': durationSeconds,
      'status': status,
    };
  }
}
