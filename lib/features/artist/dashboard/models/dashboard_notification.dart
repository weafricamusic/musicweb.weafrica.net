import 'package:flutter/foundation.dart';

@immutable
class DashboardNotification {
  const DashboardNotification({
    required this.id,
    required this.title,
    required this.body,
    this.createdAt,
    this.read,
  });

  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool? read;

  factory DashboardNotification.fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final title = (row['title'] ?? row['type'] ?? 'Notification').toString();
    final body = (row['body'] ?? row['message'] ?? '').toString();
    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw.toString());
    final read = row['read'];

    return DashboardNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      read: read is bool ? read : null,
    );
  }
}
