/// Live session model - represents an active live stream
class LiveSessionModel {
  final String id;
  final String channelId;
  final String hostId;
  final String? hostName;
  final String? hostAvatarUrl;
  final String? title;
  final String? thumbnailUrl;
  final String status;
  final bool isLive;
  final String liveType;
  final int viewerCount;
  final int giftCount;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? lastHeartbeat;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LiveSessionModel({
    required this.id,
    required this.channelId,
    required this.hostId,
    this.hostName,
    this.hostAvatarUrl,
    this.title,
    this.thumbnailUrl,
    this.status = 'live',
    this.isLive = true,
    this.liveType = 'solo',
    this.viewerCount = 0,
    this.giftCount = 0,
    this.startedAt,
    this.endedAt,
    this.lastHeartbeat,
    this.createdAt,
    this.updatedAt,
  });

  factory LiveSessionModel.fromJson(Map<String, dynamic> json) {
    return LiveSessionModel(
      id: json['id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      hostId: json['host_id']?.toString() ?? '',
      hostName: json['host_name']?.toString(),
      hostAvatarUrl: json['host_avatar_url']?.toString(),
      title: json['title']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      status: json['status']?.toString() ?? 'live',
      isLive: json['is_live'] ?? true,
      liveType: json['live_type']?.toString() ?? 'solo',
      viewerCount: json['viewer_count'] ?? 0,
      giftCount: json['gift_count'] ?? 0,
      startedAt: json['started_at'] != null 
          ? DateTime.parse(json['started_at'].toString())
          : null,
      endedAt: json['ended_at'] != null 
          ? DateTime.parse(json['ended_at'].toString())
          : null,
      lastHeartbeat: json['last_heartbeat'] != null 
          ? DateTime.parse(json['last_heartbeat'].toString())
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'channel_id': channelId,
    'host_id': hostId,
    'host_name': hostName,
    'host_avatar_url': hostAvatarUrl,
    'title': title,
    'thumbnail_url': thumbnailUrl,
    'status': status,
    'is_live': isLive,
    'live_type': liveType,
    'viewer_count': viewerCount,
    'gift_count': giftCount,
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'last_heartbeat': lastHeartbeat?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}