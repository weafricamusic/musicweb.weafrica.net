import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

class LiveSessionData {
  final String id;
  final String liveId;
  final String channelId;
  final String token;

  LiveSessionData({
    required this.id,
    required this.liveId,
    required this.channelId,
    required this.token,
  });

  factory LiveSessionData.fromMap(Map<String, dynamic> map) {
    return LiveSessionData(
      id: (map['id'] ?? '').toString(),
      liveId: (map['live_id'] ?? map['liveId'] ?? '').toString(),
      channelId: (map['channel_id'] ?? map['channelId'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
    );
  }
}

class LiveSessionJoinResponse {
  final LiveSessionData? data;
  final String? error;

  LiveSessionJoinResponse({this.data, this.error});
}

/// Service for managing live session lifecycle.
class LiveSessionService {
  static final LiveSessionService _instance = LiveSessionService._internal();
  static LiveSessionService get instance => _instance;
  
  factory LiveSessionService() => _instance;
  
  LiveSessionService._internal();

  String? _currentSessionId;

  Future<String> startSession({
    required String userId,
    required String userName,
    String? battleId,
  }) async {
    debugPrint('LiveSessionService: startSession for user=$userName');
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    return _currentSessionId!;
  }

  Future<void> endSession({required String sessionId}) async {
    debugPrint('LiveSessionService: endSession sessionId=$sessionId');
    if (_currentSessionId == sessionId) {
      _currentSessionId = null;
    }
  }

  Future<LiveSessionJoinResponse> joinSession(
    String channelId,
    String userId, {
    bool asBroadcaster = false,
    String? battleId,
  }) async {
    try {
      final uri = const ApiUriBuilder().build('/api/live/join');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'channel_id': channelId,
          'user_id': userId,
          'as_broadcaster': asBroadcaster,
          'battle_id': battleId,
        }),
        requireAuth: true,
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        return LiveSessionJoinResponse(data: LiveSessionData.fromMap(decoded as Map<String, dynamic>));
      }
      return LiveSessionJoinResponse(error: 'Failed to join session: ${res.statusCode}');
    } catch (e) {
      return LiveSessionJoinResponse(error: e.toString());
    }
  }

  String? get currentSessionId => _currentSessionId;
}
