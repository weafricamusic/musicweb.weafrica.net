import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

/// Represents the status of a live battle.
class BattleStatus {
  final String battleId;
  final String channelId;
  final String hostAId;
  final String hostBId;
  final String status;
  final int? durationSeconds;
  final bool isLive;

  BattleStatus({
    required this.battleId,
    required this.channelId,
    required this.hostAId,
    required this.hostBId,
    required this.status,
    this.durationSeconds,
    this.isLive = false,
  });

  factory BattleStatus.fromMap(Map<String, dynamic> map) {
    return BattleStatus(
      battleId: (map['id'] ?? map['battle_id'] ?? '').toString(),
      channelId: (map['channel_id'] ?? '').toString(),
      hostAId: (map['host_a_id'] ?? '').toString(),
      hostBId: (map['host_b_id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      durationSeconds: map['duration_seconds'] as int?,
      isLive: (map['status'] ?? '').toString().toLowerCase() == 'live',
    );
  }
}

class BattleStatusResponse {
  final BattleStatus? data;
  final String? error;

  BattleStatusResponse({this.data, this.error});
}

/// Service for tracking battle status changes.
class BattleStatusService {
  static final BattleStatusService _instance = BattleStatusService._internal();
  static BattleStatusService get instance => _instance;

  factory BattleStatusService() => _instance;

  BattleStatusService._internal();

  StreamSubscription? _subscription;

  Future<BattleStatusResponse> fetchStatus({required String battleId}) async {
    try {
      final uri = const ApiUriBuilder().build('/api/battle/status/$battleId');
      final res = await FirebaseAuthedHttp.get(uri, requireAuth: true);
      
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        return BattleStatusResponse(data: BattleStatus.fromMap(decoded as Map<String, dynamic>));
      }
      return BattleStatusResponse(error: 'Failed to fetch status: ${res.statusCode}');
    } catch (e) {
      return BattleStatusResponse(error: e.toString());
    }
  }

  void startListening({required String battleId}) {
    debugPrint('BattleStatusService: startListening for battleId=$battleId');
    // Implementation would listen to Supabase realtime changes
  }

  void stopListening() {
    debugPrint('BattleStatusService: stopListening');
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
