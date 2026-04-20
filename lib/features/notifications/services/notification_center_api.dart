import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:weafrica_music/app/network/firebase_authed_http.dart';
import 'package:weafrica_music/app/config/api_env.dart';

@immutable
class NotificationCenterItem {
  const NotificationCenterItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.createdAt,
    required this.read,
    required this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool read;
  final DateTime? readAt;

  static NotificationCenterItem fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now().toUtc();
      final s = v.toString();
      return DateTime.tryParse(s)?.toUtc() ?? DateTime.now().toUtc();
    }

    return NotificationCenterItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      body: (json['body'] ?? '').toString(),
      type: (json['type'] ?? 'general').toString(),
      data: (json['data'] is Map)
          ? Map<String, dynamic>.from(json['data'] as Map)
          : <String, dynamic>{},
      createdAt: parseDate(json['created_at']),
      read: json['read'] == true,
      readAt: json['read_at'] != null ? parseDate(json['read_at']) : null,
    );
  }
}

class NotificationCenterApi {
  NotificationCenterApi._();

  static final NotificationCenterApi instance = NotificationCenterApi._();

  String get _baseUrl => ApiEnv.baseUrl;

  Future<int> getUnreadCount() async {
    final uri = Uri.parse('$_baseUrl/api/notifications/unread_count');
    final res = await FirebaseAuthedHttp.get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Unread count request failed (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return (decoded['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<NotificationCenterItem>> list({int limit = 40, int offset = 0}) async {
    final uri = Uri.parse('$_baseUrl/api/notifications')
        .replace(queryParameters: <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    });

    final res = await FirebaseAuthedHttp.get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Notifications request failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final items = decoded['items'];
    if (items is! List) return <NotificationCenterItem>[];
    return items
        .whereType<Map>()
        .map((e) => NotificationCenterItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<void> markRead(String id) async {
    final uri = Uri.parse('$_baseUrl/api/notifications/mark_read');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': id}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Mark read failed (${res.statusCode})');
    }
  }

  Future<void> markAllRead() async {
    final uri = Uri.parse('$_baseUrl/api/notifications/mark_all_read');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Mark all read failed (${res.statusCode})');
    }
  }
}
