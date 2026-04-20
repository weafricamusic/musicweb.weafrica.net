import 'package:flutter/foundation.dart';

enum CreatorRole {
  artist,
  dj,
}

extension CreatorRoleX on CreatorRole {
  String get id => switch (this) {
        CreatorRole.artist => 'artist',
        CreatorRole.dj => 'dj',
      };

  static CreatorRole? tryParse(String? value) {
    final v = value?.trim().toLowerCase();
    return switch (v) {
      'artist' => CreatorRole.artist,
      'dj' => CreatorRole.dj,
      _ => null,
    };
  }
}

@immutable
class CreatorProfile {
  const CreatorProfile({
    required this.id,
    required this.role,
    required this.displayName,
    this.userId,
    this.avatarUrl,
    this.bio,
    this.createdAt,
  });

  final String id;
  final String? userId;
  final CreatorRole role;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final DateTime? createdAt;

  static CreatorProfile fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final role = CreatorRoleX.tryParse(row['role']?.toString()) ?? CreatorRole.artist;
    final displayName = _firstNonEmpty(<Object?>[
      row['display_name'],
      row['stage_name'],
      row['artist_name'],
      row['dj_name'],
      row['name'],
      row['full_name'],
      row['username'],
      row['title'],
      row['artist'],
      row['stage'],
      row['email'],
    ]);

    DateTime? createdAt;
    final rawCreatedAt = row['created_at'];
    if (rawCreatedAt is String) createdAt = DateTime.tryParse(rawCreatedAt);

    String? s(String key) {
      final v = row[key];
      if (v == null) return null;
      final out = v.toString().trim();
      return out.isEmpty ? null : out;
    }

    return CreatorProfile(
      id: id.isEmpty ? displayName : id,
      role: role,
      displayName: displayName.isEmpty ? 'Unknown' : displayName,
      userId: s('user_id'),
      avatarUrl: s('avatar_url'),
      bio: s('bio'),
      createdAt: createdAt,
    );
  }

  static String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
