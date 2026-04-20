import 'dart:convert';

import 'package:weafrica_music/app/config/api_env.dart';
import 'package:weafrica_music/app/network/firebase_authed_http.dart';

class CreatorInboxApi {
  CreatorInboxApi._();

  static final CreatorInboxApi instance = CreatorInboxApi._();

  String get _baseUrl => ApiEnv.baseUrl;

  Future<List<Map<String, dynamic>>> listMessages({
    required String role,
    int limit = 120,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/inbox/messages').replace(
      queryParameters: <String, String>{
        'role': role,
        'limit': '$limit',
      },
    );
    final res = await FirebaseAuthedHttp.get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Inbox request failed (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final items = decoded['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> markRead({required String role, required String id}) async {
    final uri = Uri.parse('$_baseUrl/api/inbox/messages/mark_read');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'role': role, 'id': id}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Inbox mark-read failed (${res.statusCode})');
    }
  }

  Future<void> reply({
    required String role,
    required String message,
    String? threadId,
    String? recipientUid,
    String? recipientName,
    String? senderName,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/inbox/messages/reply');
    final payload = <String, dynamic>{
      'role': role,
      'message': message,
      if (threadId != null && threadId.trim().isNotEmpty) 'thread_id': threadId,
      if (recipientUid != null && recipientUid.trim().isNotEmpty) 'recipient_uid': recipientUid,
      if (recipientName != null && recipientName.trim().isNotEmpty) 'recipient_name': recipientName,
      if (senderName != null && senderName.trim().isNotEmpty) 'sender_name': senderName,
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Inbox reply failed (${res.statusCode})');
    }
  }
}
