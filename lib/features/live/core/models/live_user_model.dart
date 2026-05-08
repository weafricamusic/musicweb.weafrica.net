/// Represents a user (artist, co-host, or competitor) in a live session.
class LiveUserModel {
  final String id;
  final String name;
  final String? avatarUrl;
  final int uid; // Agora UID
  final bool isHost;
  final bool isMuted;
  final bool isVideoOff;

  const LiveUserModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.uid,
    this.isHost = false,
    this.isMuted = false,
    this.isVideoOff = false,
  });

  factory LiveUserModel.fromJson(Map<String, dynamic> json) {
    return LiveUserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      avatarUrl: json['avatar_url']?.toString(),
      uid: json['uid'] is int
          ? json['uid'] as int
          : int.tryParse(json['uid']?.toString() ?? '0') ?? 0,
      isHost: json['is_host'] == true,
      isMuted: json['is_muted'] == true,
      isVideoOff: json['is_video_off'] == true,
    );
  }

  LiveUserModel copyWith({
    bool? isMuted,
    bool? isVideoOff,
  }) {
    return LiveUserModel(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      uid: uid,
      isHost: isHost,
      isMuted: isMuted ?? this.isMuted,
      isVideoOff: isVideoOff ?? this.isVideoOff,
    );
  }
}