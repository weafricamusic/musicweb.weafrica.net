/// Firestore / Supabase live session document model.
class LiveSessionModel {
  final String id;
  final String hostId;
  final String hostName;
  final String channelId;
  final String title;
  final String? category;
  final String status;
  final bool isLive;
  final int viewerCount;
  final String? thumbnailUrl;
  final DateTime createdAt;

  const LiveSessionModel({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.channelId,
    required this.title,
    this.category,
    required this.status,
    required this.isLive,
    this.viewerCount = 0,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory LiveSessionModel.fromJson(Map<String, dynamic> json) {
    return LiveSessionModel(
      id: json['id']?.toString() ?? '',
      hostId: json['host_id']?.toString() ?? '',
      hostName: json['host_name']?.toString() ?? 'Live Host',
      channelId: json['channel_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Stream',
      category: json['category']?.toString(),
      status: json['status']?.toString() ?? 'idle',
      isLive: json['is_live'] == true,
      viewerCount: json['viewer_count'] is int
          ? json['viewer_count'] as int
          : int.tryParse(json['viewer_count']?.toString() ?? '0') ?? 0,
      thumbnailUrl: json['thumbnail_url']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'host_id': hostId,
    'host_name': hostName,
    'channel_id': channelId,
    'title': title,
    'category': category,
    'status': status,
    'is_live': isLive,
    'viewer_count': viewerCount,
    'thumbnail_url': thumbnailUrl,
    'created_at': createdAt.toIso8601String(),
  };
}