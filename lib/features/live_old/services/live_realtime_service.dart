import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gift_model.dart';

class LiveRealtimeService {
  LiveRealtimeService({
    required this.channelId,
    required this.competitor1Id,
    required this.competitor2Id,
  });

  final String channelId;
  final String competitor1Id;
  String competitor2Id;

  final SupabaseClient _supabase = Supabase.instance.client;

  final StreamController<int> _viewerCountController = StreamController<int>.broadcast();
  final StreamController<int> _totalGiftsController = StreamController<int>.broadcast();
  final StreamController<Map<String, int>> _scoreController = StreamController<Map<String, int>>.broadcast();
  final StreamController<GiftModel> _giftController = StreamController<GiftModel>.broadcast();

  StreamSubscription<List<Map<String, dynamic>>>? _sessionSub;
  Timer? _giftPollTimer;
  DateTime? _lastGiftCreatedAt;

  final Set<String> _seenGiftIds = <String>{};
  bool _connected = false;

  int _giftCount = 0;
  int _score1 = 0;
  int _score2 = 0;

  Stream<int> get viewerCountStream => _viewerCountController.stream;
  Stream<int> get totalGiftsStream => _totalGiftsController.stream;
  Stream<Map<String, int>> get scoreStream => _scoreController.stream;
  Stream<GiftModel> get giftStream => _giftController.stream;

  GiftType _giftTypeFromId(String giftId) {
    final s = giftId.trim().toLowerCase();
    if (s.contains('rose') || s.contains('flor')) return GiftType.rose;
    if (s.contains('gift') || s.contains('present')) return GiftType.gift;
    if (s.contains('balloon')) return GiftType.balloon;
    if (s.contains('star')) return GiftType.star;
    if (s.contains('firework') || s.contains('celebration') || s.contains('confetti')) {
      return GiftType.fireworks;
    }
    if (s.contains('rainbow') || s.contains('aurora')) return GiftType.rainbow;
    if (s.contains('fire') || s.contains('flame')) return GiftType.fire;
    if (s.contains('love') || s.contains('heart') || s.contains('rose')) return GiftType.love;
    if (s.contains('mic') || s.contains('microphone')) return GiftType.mic;
    if (s.contains('diamond') || s.contains('gem')) return GiftType.diamond;
    if (s.contains('crown') || s.contains('trophy')) return GiftType.crown;
    if (s.contains('rocket')) return GiftType.rocket;
    return GiftType.fire;
  }

  Future<void> _loadInitialScores() async {
    final c1 = competitor1Id.trim();
    final c2 = competitor2Id.trim();
    final ids = <String>[c1, c2].where((s) => s.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) return;

    try {
      final rows = await _supabase
          .from('live_gift_events')
          .select('to_host_id, score:score_coins.sum(), coins:coin_cost.sum()')
          .eq('channel_id', channelId)
          .inFilter('to_host_id', ids);

      int s1 = 0;
      int s2 = 0;
      for (final r in (rows as List).whereType<Map>()) {
        final m = r.map((k, v) => MapEntry(k.toString(), v));
        final to = (m['to_host_id'] ?? '').toString().trim();
        final scoreRaw = m['score'];
        final coinsRaw = m['coins'];
        final coins = (coinsRaw is num) ? coinsRaw.toInt() : int.tryParse('$coinsRaw') ?? 0;
        final score = (scoreRaw is num) ? scoreRaw.toInt() : int.tryParse('$scoreRaw') ?? coins;
        if (to == c1) s1 = score;
        if (to == c2) s2 = score;
      }

      _score1 = s1;
      _score2 = s2;
      _scoreController.add(<String, int>{'competitor1': _score1, 'competitor2': _score2});
    } catch (e) {
      developer.log('Initial score load failed', name: 'WEAFRICA.Live', error: e);
    }
  }

  Future<void> setCompetitor2Id(String userId) async {
    final next = userId.trim();
    if (next == competitor2Id.trim()) return;

    competitor2Id = next;
    await _loadInitialScores();
  }

  Future<void> _pollGiftEvents() async {
    if (!_connected) return;
    try {
      var q = _supabase
          .from('live_gift_events')
          .select('id,gift_id,coin_cost,score_coins,to_host_id,sender_name,created_at')
          .eq('channel_id', channelId);

      final cursor = _lastGiftCreatedAt;
      if (cursor != null) {
        q = q.gt('created_at', cursor.toIso8601String());
      }

      final rows = await q.order('created_at', ascending: true).limit(50);

      for (final raw in rows) {
        final id = (raw['id'] ?? '').toString().trim();
        if (id.isEmpty || _seenGiftIds.contains(id)) continue;

        final createdAt = DateTime.tryParse((raw['created_at'] ?? '').toString());
        if (createdAt != null) {
          if (_lastGiftCreatedAt == null || createdAt.isAfter(_lastGiftCreatedAt!)) {
            _lastGiftCreatedAt = createdAt;
          }
        }

        _seenGiftIds.add(id);
        _giftCount += 1;
        _totalGiftsController.add(_giftCount);

        final giftId = (raw['gift_id'] ?? '').toString().trim().toLowerCase();
        final coinRaw = raw['coin_cost'];
        final coin = (coinRaw is num) ? coinRaw.toInt() : int.tryParse('$coinRaw') ?? 0;
        final scoreRaw = raw['score_coins'];
        final score = (scoreRaw is num) ? scoreRaw.toInt() : int.tryParse('$scoreRaw') ?? coin;
        final to = (raw['to_host_id'] ?? '').toString().trim();
        final senderName = (raw['sender_name'] ?? 'Fan').toString();

        if (to.isNotEmpty) {
          if (to == competitor1Id) {
            _score1 += score;
          } else if (to == competitor2Id) {
            _score2 += score;
          }
          _scoreController.add(<String, int>{'competitor1': _score1, 'competitor2': _score2});
        }

        _giftController.add(
          GiftModel(
            id: id,
            type: _giftTypeFromId(giftId),
            senderName: senderName,
            receiverId: to,
            coinValue: coin,
            scoreValue: score,
          ),
        );
      }
    } catch (e) {
      developer.log('Gift polling failed', name: 'WEAFRICA.Live', error: e);
    }
  }

  Future<void> connect() async {
    if (_connected) return;
    _connected = true;

    try {
      _sessionSub = _supabase
          .from('live_sessions')
          .stream(primaryKey: const ['id'])
          .eq('channel_id', channelId)
          .listen((rows) {
        if (rows.isEmpty) return;
        final row = rows.first;
        final viewerCount = (row['viewer_count'] as int?) ?? 0;
        _viewerCountController.add(viewerCount);
      });
    } catch (e) {
      developer.log('LiveRealtimeService session stream failed', error: e);
    }

    await _loadInitialScores();

    _lastGiftCreatedAt = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
    _giftPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: discarded_futures
      _pollGiftEvents();
    });
  }

  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;

    _giftPollTimer?.cancel();
    _giftPollTimer = null;

    await _sessionSub?.cancel();
    _sessionSub = null;
  }

  /// Permanently disposes this service.
  ///
  /// Unlike [disconnect], this closes the underlying stream controllers and
  /// should only be called when the owning screen is disposed.
  Future<void> dispose() async {
    await disconnect();

    await _viewerCountController.close();
    await _totalGiftsController.close();
    await _scoreController.close();
    await _giftController.close();
  }
}
