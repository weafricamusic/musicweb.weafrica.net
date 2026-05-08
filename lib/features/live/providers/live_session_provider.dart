import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

final liveSessionProvider =
    AsyncNotifierProvider<LiveSessionNotifier, Map<String, dynamic>?>(
      LiveSessionNotifier.new,
    );

class LiveSessionNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  String? _currentSessionId;

  String? get currentSessionId => _currentSessionId;

  @override
  FutureOr<Map<String, dynamic>?> build() async {
    return null;
  }

  SupabaseClient get _supabase => ref.read(supabaseClientProvider);

  Future<String> startLive({
    required String hostId,
    required String hostName,
    required String title,
    required String category,
    String? thumbnailUrl,
  }) async {
    final channelName =
        'solo_${hostId}_${DateTime.now().millisecondsSinceEpoch}';

    final response = await _supabase
        .from('live_sessions')
        .insert({
          'host_id': hostId,
          'host_name': hostName.trim().isEmpty ? 'Live Host' : hostName.trim(),
          'channel_id': channelName,
          'title': title,
          'category': category,
          'status': 'live',
          'is_live': true,
        })
        .select()
        .single();

    _currentSessionId = response['id'] as String;
    state = AsyncValue.data(response);
    return _currentSessionId!;
  }

  Future<void> endLive() async {
    final current = state.asData?.value;

    final sessionId = _currentSessionId ?? current?['id']?.toString();
    final channelId = current?['channel_id']?.toString();

    if (sessionId == null && (channelId == null || channelId.isEmpty)) {
      return;
    }

    final update = {'status': 'ended', 'is_live': false};

    if (sessionId != null && sessionId.isNotEmpty) {
      await _supabase.from('live_sessions').update(update).eq('id', sessionId);
    } else {
      await _supabase
          .from('live_sessions')
          .update(update)
          .eq('channel_id', channelId!);
    }

    state = const AsyncValue.data(null);
    _currentSessionId = null;
  }
}
