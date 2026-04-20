import 'dart:developer' as developer;
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/utils/app_result.dart';
import '../models/chat_message_model.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  Future<AppResult<void>> sendMessage({
    required String liveId,
    required String userId,
    required String userName,
    required String message,
  }) async {
    try {
      final bearer = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
      if (bearer.isEmpty) {
        return const AppFailure(userMessage: 'Please sign in and try again.');
      }

      final uri = _uriBuilder.build('/api/live/chat/send');
      final payload = <String, Object?>{
        'live_id': liveId,
        'message': message,
        'username': userName,
      };

      final res = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 429) {
        return const AppFailure(userMessage: 'Slow down — one message every 2 seconds.');
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        var msg = '';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            msg = (decoded['message'] ?? decoded['error_description'] ?? decoded['error'] ?? '').toString().trim();
          }
        } catch (_) {
          // Ignore decode errors; fall back to generic message.
        }

        developer.log('Send message failed', error: 'HTTP ${res.statusCode} ${res.body}');
        return AppFailure(userMessage: msg.isNotEmpty ? msg : 'Could not send message. Please try again.');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        return const AppFailure(userMessage: 'Could not send message. Please try again.');
      }
      return const AppSuccess(null);
    } catch (e, st) {
      developer.log('Send message failed', error: e, stackTrace: st);
      return const AppFailure(userMessage: 'Could not send message. Please try again.');
    }
  }

  /// Optional realtime stream. UI may choose to ignore failures.
  Stream<List<ChatMessageModel>> watchMessages({required String liveId, int limit = 50}) {
    return _supabase
        .from('live_messages')
        .stream(primaryKey: ['id'])
        .eq('live_id', liveId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) {
          return rows
              .map(
                (r) => ChatMessageModel(
                  id: (r['id'] ?? '').toString(),
                  userId: (r['user_id'] ?? '').toString(),
                  userName: (r['username'] ?? 'User').toString(),
                  message: (r['message'] ?? '').toString(),
                  timestamp: DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now(),
                  isGift: (r['kind'] ?? '').toString() == 'gift',
                ),
              )
              .toList(growable: false);
        });
  }
}
