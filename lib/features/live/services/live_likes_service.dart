import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLikesService {
  LiveLikesService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Stream<int> watchLikeCount({required String channelId}) {
    final channel = channelId.trim();
    if (channel.isEmpty) {
      return const Stream<int>.empty();
    }

    return _supabase
        .from('live_like_counters')
        .stream(primaryKey: const ['channel_id'])
        .eq('channel_id', channel)
        .map((rows) {
      if (rows.isEmpty) return 0;
      final first = rows.first;
      final raw = first['count'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? 0;
    });
  }

  Future<int> sendLike({
    required String channelId,
    int delta = 1,
  }) async {
    final channel = channelId.trim();
    if (channel.isEmpty) {
      throw ArgumentError('channelId is required');
    }

    final safeDelta = delta < 1 ? 1 : (delta > 1000 ? 1000 : delta);

    try {
      final res = await _supabase.rpc(
        'increment_live_likes_by',
        params: <String, dynamic>{
          'p_channel_id': channel,
          'p_delta': safeDelta,
        },
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse('$res') ?? 0;
    } catch (_) {
      final res = await _supabase.rpc(
        'increment_live_likes',
        params: <String, dynamic>{
          'p_channel_id': channel,
        },
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse('$res') ?? 0;
    }
  }
}
