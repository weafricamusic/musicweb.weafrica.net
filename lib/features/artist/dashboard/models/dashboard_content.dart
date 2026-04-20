import 'package:flutter/foundation.dart';

@immutable
class DashboardVideoItem {
  const DashboardVideoItem({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? thumbnailUrl;
  final DateTime? createdAt;

  factory DashboardVideoItem.fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final titleRaw = (row['title'] ?? row['name'] ?? '').toString().trim();
    final title = titleRaw.isEmpty ? 'Untitled video' : titleRaw;
    final thumbRaw = (row['thumbnail_url'] ?? row['thumbnail'] ?? row['image_url'] ?? '').toString().trim();
    final thumbnailUrl = thumbRaw.isEmpty ? null : thumbRaw;

    final createdAtRaw = row['created_at'] ?? row['createdAt'];
    final createdAt = createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw.toString());

    return DashboardVideoItem(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      createdAt: createdAt,
    );
  }
}
