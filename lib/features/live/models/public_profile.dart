// lib/features/live/models/public_profile.dart

class PublicProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String userType;
  final int followerCount;
  final DateTime? lastActive;

  PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.userType,
    required this.followerCount,
    this.lastActive,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final lastActiveRaw = json['last_active'] ?? json['updated_at'];
    return PublicProfile(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['full_name'] ?? json['name'] ?? '',
      avatarUrl: json['avatar_url'],
      userType: json['role'] ?? json['user_type'] ?? 'artist',
      followerCount: json['follower_count'] ?? json['followers'] ?? 0,
      lastActive: lastActiveRaw != null
          ? DateTime.tryParse(lastActiveRaw.toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'role': userType,
    'user_type': userType,
    'follower_count': followerCount,
    'last_active': lastActive?.toIso8601String(),
  };
}
