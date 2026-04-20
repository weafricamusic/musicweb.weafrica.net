import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReelLikeState {
  const ReelLikeState({
    required this.isLikedByMe,
    required this.likesCount,
  });

  final bool isLikedByMe;
  final int likesCount;

  ReelLikeState copyWith({bool? isLikedByMe, int? likesCount}) {
    return ReelLikeState(
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      likesCount: likesCount ?? this.likesCount,
    );
  }
}

class ReelLikeManager extends ChangeNotifier {
  ReelLikeManager({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Map<String, ReelLikeState> _byReelId = <String, ReelLikeState>{};

  ReelLikeState stateFor(String reelId, {required int fallbackCount}) {
    return _byReelId[reelId] ??
        ReelLikeState(
          isLikedByMe: false,
          likesCount: fallbackCount,
        );
  }

  void seed({required String reelId, required int likesCount, bool isLikedByMe = false}) {
    _byReelId.putIfAbsent(
      reelId,
      () => ReelLikeState(isLikedByMe: isLikedByMe, likesCount: likesCount),
    );
  }

  void applyServerCount({required String reelId, required int likesCount}) {
    final current = _byReelId[reelId];
    if (current == null) {
      _byReelId[reelId] = ReelLikeState(isLikedByMe: false, likesCount: likesCount);
    } else {
      _byReelId[reelId] = current.copyWith(likesCount: likesCount.clamp(0, 1 << 31));
    }
    notifyListeners();
  }

  Future<dynamic> _runToggleRpc(String reelId) async {
    return _client.rpc('toggle_reel_like', params: <String, dynamic>{
      'p_reel_id': reelId,
    });
  }

  bool _isUnauthorized(Object error) {
    if (error is AuthException) return true;
    if (error is PostgrestException) {
      final c = (error.code ?? '').toUpperCase();
      if (c == '401' || c == 'PGRST301' || c == 'PGRST302') return true;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('not authenticated') ||
        msg.contains('jwt') ||
        msg.contains('401') ||
        msg.contains('auth');
  }

  Future<Map<String, dynamic>> _retryToggle(String reelId) async {
    Object? last;
    var delay = const Duration(milliseconds: 300);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final raw = await _runToggleRpc(reelId).timeout(const Duration(seconds: 8));
        if (raw is Map<String, dynamic>) return raw;
        if (raw is Map) {
          return raw.map((key, value) => MapEntry(key.toString(), value));
        }
        throw StateError('toggle_reel_like returned unexpected payload');
      } on TimeoutException catch (e) {
        last = e;
      } catch (e) {
        if (_isUnauthorized(e)) rethrow;
        final msg = e.toString().toLowerCase();
        final isRetryable = msg.contains('timeout') || msg.contains('network') || msg.contains('socket');
        if (!isRetryable) rethrow;
        last = e;
      }

      if (attempt < 2) {
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }

    throw last ?? StateError('Could not toggle like');
  }

  Future<void> toggleLike(
    String reelId, {
    required int fallbackCount,
    required VoidCallback onAuthRequired,
    required void Function(String message) onError,
  }) async {
    final current = stateFor(reelId, fallbackCount: fallbackCount);
    final previous = current;

    final optimistic = current.copyWith(
      isLikedByMe: !current.isLikedByMe,
      likesCount: current.isLikedByMe ? (current.likesCount - 1).clamp(0, 1 << 31) : current.likesCount + 1,
    );

    _byReelId[reelId] = optimistic;
    notifyListeners();

    try {
      final payload = await _retryToggle(reelId);
      final liked = payload['liked'] == true;
      final likesCount = (payload['likes_count'] is num)
          ? (payload['likes_count'] as num).toInt()
          : int.tryParse('${payload['likes_count']}') ?? optimistic.likesCount;

      _byReelId[reelId] = ReelLikeState(
        isLikedByMe: liked,
        likesCount: likesCount,
      );
      notifyListeners();
    } catch (e) {
      _byReelId[reelId] = previous;
      notifyListeners();

      if (_isUnauthorized(e)) {
        onAuthRequired();
        return;
      }

      onError('Unable to update like right now. Please retry.');
    }
  }
}
