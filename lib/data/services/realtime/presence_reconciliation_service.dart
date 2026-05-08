import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/agora_service.dart';

/// Periodically reconciles Supabase live session state with Agora presence.
class PresenceReconciliationService {
  final SupabaseClient _supabase;
  final AgoraService _agora;
  Timer? _timer;

  PresenceReconciliationService(this._supabase, this._agora);

  void start({Duration interval = const Duration(seconds: 30)}) {
    stop();
    _timer = Timer.periodic(interval, (_) => _reconcile());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _reconcile() async {
    try {
        final resp = await _supabase
          .from('live_sessions')
          .select('id, channel_name, host_id')
          .eq('status', 'live');

        final List sessions = (resp as List?) ?? [];

      for (final s in sessions) {
        await _reconcileSession(Map<String, dynamic>.from(s as Map));
      }
    } catch (e, st) {
      debugPrint('PresenceReconciliation error: $e\n$st');
    }
  }

  Future<void> _reconcileSession(Map<String, dynamic> session) async {
    final sessionId = session['id'] as String?;
    final channelName = session['channel_name'] as String?;
    if (sessionId == null || channelName == null) return;

    final hostActive = await _checkHostPresence(channelName);
    if (!hostActive) {
      await _autoEndStream(sessionId);
      return;
    }

    // Remove stale viewer_sessions where joined_at older than threshold
    final staleThreshold = DateTime.now().subtract(const Duration(minutes: 2));
    await _supabase
      .from('viewer_sessions')
      .update({'left_at': DateTime.now().toIso8601String()})
      .eq('live_session_id', sessionId)
      .filter('left_at', 'is', null)
      .lt('joined_at', staleThreshold.toIso8601String());

    // Recalculate viewer count and persist
    final viewer_countResp = await _supabase
      .from('viewer_sessions')
      .select('id')
      .eq('live_session_id', sessionId)
      .filter('left_at', 'is', null);

    final int actualCount = (viewer_countResp as List?)?.length ?? 0;
    await _supabase
      .from('live_sessions')
      .update({'viewer_count': actualCount})
      .eq('id', sessionId);
  }

  Future<bool> _checkHostPresence(String channelName) async {
    // Placeholder: in production use Agora REST API or signaling channel
    // For now, rely on local Agora state when possible
    return _agora.isJoined.value;
  }

  Future<void> _autoEndStream(String sessionId) async {
    await _supabase.from('live_sessions').update({
      'status': 'ended',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);

    await _supabase
      .from('live_participants')
      .update({'left_at': DateTime.now().toIso8601String()})
      .eq('live_session_id', sessionId)
      .filter('left_at', 'is', null);

    await _supabase
      .from('viewer_sessions')
      .update({'left_at': DateTime.now().toIso8601String()})
      .eq('live_session_id', sessionId)
      .filter('left_at', 'is', null);

    debugPrint('Auto-ended stream $sessionId (host absent)');
  }

  void dispose() {
    stop();
  }
}
