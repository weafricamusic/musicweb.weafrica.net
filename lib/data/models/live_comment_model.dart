/// Live comment model - represents a chat message in a live stream
class LiveCommentModel {
  final String id;
  final String liveSessionId;
  final String userId;
  final String? username;
  final String? avatarUrl;
  final String message;
  final DateTime? createdAt;

  LiveCommentModel({
    required this.id,
    required this.liveSessionId,
    required this.userId,
    this.username,
    this.avatarUrl,
    required this.message,
    this.createdAt,
  });

  factory LiveCommentModel.fromJson(Map<String, dynamic> json) {
    return LiveCommentModel(
      id: json['id']?.toString() ?? '',
      liveSessionId: json['live_session_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      message: json['message']?.toString() ?? '',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'live_session_id': liveSessionId,
    'user_id': userId,
    'username': username,
    'avatar_url': avatarUrl,
    'message': message,
    'created_at': createdAt?.toIso8601String(),
  };
}