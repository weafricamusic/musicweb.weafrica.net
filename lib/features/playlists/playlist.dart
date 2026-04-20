import 'package:flutter/foundation.dart';

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.userId,
    required this.name,
    this.coverUrl,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? coverUrl;
  final DateTime? createdAt;

  static Playlist fromSupabase(Map<String, dynamic> row) {
    return Playlist(
      id: row['id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      coverUrl: row['cover_url']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    );
  }
}
