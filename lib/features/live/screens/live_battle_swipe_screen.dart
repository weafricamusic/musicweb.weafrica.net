import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../services/live_discovery_service.dart';
import '../services/battle_service.dart';
import '../services/live_feed_discover_service.dart';
import '../services/live_session_service.dart';
import 'battle_detail_screen.dart';
import 'consumer_battle_screen.dart';
import 'live_feed_screen.dart';

String _s(dynamic v) => (v ?? '').toString().trim();

int _stableAgoraUid(String userId) {
  final h = userId.hashCode.abs();
  final uid = h % 2000000000;
  return uid == 0 ? 1 : uid;
}

Future<_BattlePagePayload> _buildBattlePagePayload(Map<String, dynamic> row) async {
  final user = FirebaseAuth.instance.currentUser;
  final viewerId = (user?.uid ?? 'guest').trim();
  final viewerName = _s(user?.displayName).isNotEmpty ? _s(user?.displayName) : 'Viewer';

  final channelId = _s(row['channel_id']);
  final battleId = _s(row['battle_id']);
  if (channelId.isEmpty) {
    throw StateError('Missing battle channel.');
  }

  final joinRes = await LiveSessionService().joinSession(
    channelId,
    viewerId,
    battleId: battleId.isNotEmpty ? battleId : null,
  );
  final session = joinRes.data;
  if (session == null) {
    throw StateError('Could not join this battle right now.');
  }

  final battleRes = await BattleService().getBattle(
    session.id,
    battleId: battleId.isNotEmpty ? battleId : null,
  );
  final battle = battleRes.data;

  final hostName = _s(row['host_name']);
  final hostAId = _s(row['host_a_id']);
  final hostId = _s(row['host_id']);

  return _BattlePagePayload(
    sessionId: session.id,
    liveId: session.liveId,
    battleId: battle?.id ?? battleId,
    competitor1Id: battle?.competitor1Id ?? (hostAId.isNotEmpty ? hostAId : hostId),
    competitor2Id: battle?.competitor2Id ?? _s(row['host_b_id']),
    competitor1Name: battle?.competitor1Name ?? (hostName.isNotEmpty ? hostName : 'Host A'),
    competitor2Name: battle?.competitor2Name ?? 'Host B',
    competitor1Type: battle?.competitor1Type ?? 'artist',
    competitor2Type: battle?.competitor2Type ?? 'artist',
    durationSeconds: battle?.timeRemaining ?? 1800,
    currentUserId: viewerId,
    currentUserName: viewerName,
    channelId: session.channelId,
    token: session.token,
    agoraUid: _stableAgoraUid(viewerId),
  );
}

class LiveBattleSwipeScreen extends StatefulWidget {
  const LiveBattleSwipeScreen({
    super.key,
    this.initialChannelId,
  });

  final String? initialChannelId;

  @override
  State<LiveBattleSwipeScreen> createState() => _LiveBattleSwipeScreenState();
}

class _LiveBattleSwipeScreenState extends State<LiveBattleSwipeScreen> {
  final LiveFeedDiscoverService _discoverService = LiveFeedDiscoverService();
  final LiveDiscoveryService _liveDiscoveryService = LiveDiscoveryService();
  static const int _maxPayloadCacheEntries = 6;
  static const String _notifyPrefsKey = 'live_battle_notify_ids_v1';

  late final PageController _pageController;
  Timer? _emptyRefreshTimer;
  Future<List<Map<String, dynamic>>>? _upcomingBattlesFuture;
  Future<List<Map<String, dynamic>>>? _replayBattlesFuture;
  bool _refreshInFlight = false;
  Set<String> _notifyBattleIds = <String>{};
  List<Map<String, dynamic>> _battleStreams = const <Map<String, dynamic>>[];
  final Map<String, Future<_BattlePagePayload>> _payloadCache = <String, Future<_BattlePagePayload>>{};
  final List<String> _payloadCacheOrder = <String>[];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startEmptyAutoRefresh();
    unawaited(_loadNotifyPrefs());
    _load();
  }

  @override
  void dispose() {
    _emptyRefreshTimer?.cancel();
    _payloadCache.clear();
    _payloadCacheOrder.clear();
    _pageController.dispose();
    super.dispose();
  }

  void _startEmptyAutoRefresh() {
    _emptyRefreshTimer?.cancel();
    _emptyRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _loading || _refreshInFlight || _battleStreams.isNotEmpty) return;
      unawaited(_load(isAutoRefresh: true));
    });
  }

  Future<List<Map<String, dynamic>>> _fetchUpcomingBattles() async {
    return _liveDiscoveryService.listUpcomingBattles(limit: 6);
  }

  Future<List<Map<String, dynamic>>> _fetchReplayBattles() {
    return _liveDiscoveryService.listReplayBattles(limit: 6);
  }

  Future<void> _loadNotifyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_notifyPrefsKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _notifyBattleIds = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      });
    } catch (_) {
      // Ignore local storage failures; fallback still works without persistence.
    }
  }

  Future<void> _toggleNotifyUpcoming(Map<String, dynamic> row) async {
    final battleId = _s(row['battle_id']);
    if (battleId.isEmpty) return;

    final next = Set<String>.from(_notifyBattleIds);
    final enabling = !next.contains(battleId);
    if (enabling) {
      next.add(battleId);
    } else {
      next.remove(battleId);
    }

    setState(() => _notifyBattleIds = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_notifyPrefsKey, next.toList(growable: false));
    } catch (_) {
      // Do not fail UX if persistence fails.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabling ? 'Reminder enabled for this battle.' : 'Reminder removed for this battle.',
        ),
      ),
    );
  }

  void _openBattleDetail(Map<String, dynamic> row, BattleDetailMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BattleDetailScreen(row: row, mode: mode),
      ),
    );
  }

  String _formatSchedule(dynamic raw) {
    final text = _s(raw);
    final at = DateTime.tryParse(text);
    if (at == null) return 'TBA';
    final local = at.toLocal();
    final mm = local.minute.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hh:$mm';
  }

  String _countdownLabel(dynamic raw) {
    final text = _s(raw);
    final at = DateTime.tryParse(text);
    if (at == null) return 'Starts soon';
    final diff = at.toLocal().difference(DateTime.now());
    if (diff.isNegative) return 'Starting now';
    if (diff.inHours >= 1) return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes >= 1) return 'In ${diff.inMinutes}m';
    return 'In <1m';
  }

  void _openSoloLives() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LiveFeedScreen()),
    );
  }

  void _touchPayloadCacheKey(String channelId) {
    _payloadCacheOrder.remove(channelId);
    _payloadCacheOrder.add(channelId);
  }

  Set<String> _protectedCacheKeys(int centerIndex) {
    final keys = <String>{};
    for (var i = centerIndex; i <= centerIndex + 2; i++) {
      if (i < 0 || i >= _battleStreams.length) continue;
      final channelId = _s(_battleStreams[i]['channel_id']);
      if (channelId.isNotEmpty) {
        keys.add(channelId);
      }
    }
    return keys;
  }

  void _prunePayloadCache({required Set<String> protectedKeys}) {
    if (_payloadCache.length <= _maxPayloadCacheEntries) return;

    var safety = 0;
    while (_payloadCache.length > _maxPayloadCacheEntries && safety < 100) {
      safety++;
      String? evictionKey;
      for (final key in _payloadCacheOrder) {
        if (!protectedKeys.contains(key)) {
          evictionKey = key;
          break;
        }
      }
      if (evictionKey == null) break;
      _payloadCache.remove(evictionKey);
      _payloadCacheOrder.remove(evictionKey);
    }
  }

  Future<_BattlePagePayload> _payloadForRow(Map<String, dynamic> row) {
    final channelId = _s(row['channel_id']);
    final cached = _payloadCache[channelId];
    if (cached != null) {
      _touchPayloadCacheKey(channelId);
      return cached;
    }

    final future = _buildBattlePagePayload(row);
    _payloadCache[channelId] = future;
    _touchPayloadCacheKey(channelId);
    _prunePayloadCache(protectedKeys: _protectedCacheKeys(_currentIndex));
    future.catchError((_) {
      if (_payloadCache[channelId] == future) {
        _payloadCache.remove(channelId);
        _payloadCacheOrder.remove(channelId);
      }
    });
    return future;
  }

  void _warmPayloadAt(int index) {
    if (index < 0 || index >= _battleStreams.length) return;
    _payloadForRow(_battleStreams[index]);
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _warmPayloadAt(index + 1);
    _warmPayloadAt(index + 2);
    _prunePayloadCache(protectedKeys: _protectedCacheKeys(index));
  }

  Future<bool> _isBattleStillLive(Map<String, dynamic> row) async {
    final battleId = _s(row['battle_id']);
    final channelId = _s(row['channel_id']);
    if (battleId.isEmpty && channelId.isEmpty) return false;

    try {
      var query = Supabase.instance.client
          .from('live_battles')
          .select('battle_id')
          .eq('status', 'live');

      if (battleId.isNotEmpty) {
        query = query.eq('battle_id', battleId);
      } else {
        query = query.eq('channel_id', channelId);
      }

      final rows = await query.limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _autoAdvanceToNext(int index) async {
    if (!mounted || _currentIndex != index) return;

    for (var next = index + 1; next < _battleStreams.length; next++) {
      final row = _battleStreams[next];
      final isLive = await _isBattleStillLive(row);
      if (!mounted || _currentIndex != index) return;
      if (!isLive) continue;

      try {
        await _payloadForRow(row);
      } catch (_) {
        continue;
      }

      if (!mounted || _currentIndex != index) return;

      await _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
      return;
    }

    if (!mounted || _currentIndex != index) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No more live battles right now.')),
    );
  }

  Future<void> _load({bool isAutoRefresh = false}) async {
    _refreshInFlight = true;
    if (!isAutoRefresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      _payloadCache.clear();
      _payloadCacheOrder.clear();

      final sessions = await _discoverService.fetchLiveNow(limit: 60);
      final liveBattlesRaw = await Supabase.instance.client
          .from('live_battles')
          .select('battle_id,channel_id,host_a_id,host_b_id,status,title')
          .eq('status', 'live')
          .order('started_at', ascending: false)
          .limit(60);

      final liveBattles = (liveBattlesRaw as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList(growable: false);

      final byChannel = <String, Map<String, dynamic>>{};
      for (final row in liveBattles) {
        final c = _s(row['channel_id']);
        if (c.isEmpty) continue;
        byChannel[c] = row;
      }

      final merged = <Map<String, dynamic>>[];
      for (final session in sessions) {
        final c = _s(session['channel_id']);
        if (c.isEmpty) continue;
        final battle = byChannel[c];
        if (battle == null) continue;

        merged.add(<String, dynamic>{
          ...session,
          ...battle,
          'channel_id': c,
        });
      }

      if (!mounted) return;

      var initialIndex = 0;
      final initialChannel = _s(widget.initialChannelId);
      if (initialChannel.isNotEmpty) {
        final idx = merged.indexWhere((m) => _s(m['channel_id']) == initialChannel);
        if (idx >= 0) {
          initialIndex = idx;
        }
      }

      setState(() {
        _battleStreams = merged;
        _currentIndex = initialIndex;
        _loading = false;
        if (merged.isEmpty) {
          _upcomingBattlesFuture = _fetchUpcomingBattles();
          _replayBattlesFuture = _fetchReplayBattles();
        } else {
          _upcomingBattlesFuture = null;
          _replayBattlesFuture = null;
        }
      });

      _warmPayloadAt(initialIndex);
      _warmPayloadAt(initialIndex + 1);
      _warmPayloadAt(initialIndex + 2);
      _prunePayloadCache(protectedKeys: _protectedCacheKeys(initialIndex));

      if (merged.isNotEmpty && initialIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageController.jumpToPage(initialIndex);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load live battles. Pull down to retry.';
        _upcomingBattlesFuture = _upcomingBattlesFuture ?? _fetchUpcomingBattles();
        _replayBattlesFuture = _replayBattlesFuture ?? _fetchReplayBattles();
      });
    } finally {
      _refreshInFlight = false;
    }
  }

  Widget _buildUpcomingBattleCard(Map<String, dynamic> row) {
    final title = _s(row['title']).isEmpty ? 'Scheduled battle' : _s(row['title']);
    final hostA = _s(row['host_a_id']).isEmpty ? 'Host A' : _s(row['host_a_id']);
    final hostB = _s(row['host_b_id']).isEmpty ? 'TBD' : _s(row['host_b_id']);
    final when = _formatSchedule(row['scheduled_at']);
    final countdown = _countdownLabel(row['scheduled_at']);
    final category = _s(row['category']);
    final tier = _s(row['access_tier']);
    final battleId = _s(row['battle_id']);
    final isNotified = battleId.isNotEmpty && _notifyBattleIds.contains(battleId);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openBattleDetail(row, BattleDetailMode.upcoming),
      child: Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '$hostA vs $hostB',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70),
          ),
          if (category.isNotEmpty || tier.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${category.isEmpty ? 'Battle' : category}${tier.isEmpty ? '' : ' • ${tier.toUpperCase()}'}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const Spacer(),
          Text(
            when,
            style: const TextStyle(color: WeAfricaColors.gold, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            countdown,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => unawaited(_toggleNotifyUpcoming(row)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Text(isNotified ? 'Reminder set' : 'Notify me'),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildReplayBattleCard(Map<String, dynamic> row) {
    final title = _s(row['title']).isEmpty ? 'Battle replay' : _s(row['title']);
    final category = _s(row['category']);
    final endedAt = _s(row['ended_at']);
    final when = _formatSchedule(endedAt);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openBattleDetail(row, BattleDetailMode.replay),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              category.isEmpty ? 'Ended battle' : category,
              style: const TextStyle(color: Colors.white70),
            ),
            const Spacer(),
            Text(
              'Ended $when',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'View details',
                style: TextStyle(color: WeAfricaColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackContent() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
            children: [
              const Icon(Icons.sports_martial_arts_rounded, size: 72, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'No Live Battles Right Now',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Artists are preparing to go live. We will keep checking for new battles automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.notifications_none, size: 32, color: Colors.white54),
                    SizedBox(height: 12),
                    Text(
                      'Get notified when battles start',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white54, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Auto-refresh every 30 seconds',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Live battles'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_battleStreams.isEmpty) {
      return _buildFallbackContent();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _battleStreams.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final row = _battleStreams[index];
              return _BattleLivePage(
                key: ValueKey(_s(row['channel_id'])),
                row: row,
                preloadedPayloadFuture: _payloadForRow(row),
                onBattleEnded: () => unawaited(_autoAdvanceToNext(index)),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: CircleAvatar(
              backgroundColor: Colors.black.withValues(alpha: 0.55),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_currentIndex + 1}/${_battleStreams.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const Positioned(
            right: 12,
            bottom: 30,
            child: _SwipeHint(),
          ),
        ],
      ),
    );
  }
}

class _BattleLivePage extends StatefulWidget {
  const _BattleLivePage({
    super.key,
    required this.row,
    this.preloadedPayloadFuture,
    this.onBattleEnded,
  });

  final Map<String, dynamic> row;
  final Future<_BattlePagePayload>? preloadedPayloadFuture;
  final VoidCallback? onBattleEnded;

  @override
  State<_BattleLivePage> createState() => _BattleLivePageState();
}

class _BattleLivePageState extends State<_BattleLivePage> {
  bool _loading = true;
  String? _error;
  _BattlePagePayload? _payload;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final payload = await (widget.preloadedPayloadFuture ?? _buildBattlePagePayload(widget.row));

      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _open,
                  child: const Text('Retry battle'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _payload;
    if (p == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Battle unavailable',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return ConsumerBattleScreen(
      sessionId: p.sessionId,
      liveId: p.liveId,
      battleId: p.battleId,
      competitor1Id: p.competitor1Id,
      competitor2Id: p.competitor2Id,
      competitor1Name: p.competitor1Name,
      competitor2Name: p.competitor2Name,
      competitor1Type: p.competitor1Type,
      competitor2Type: p.competitor2Type,
      durationSeconds: p.durationSeconds,
      currentUserId: p.currentUserId,
      currentUserName: p.currentUserName,
      channelId: p.channelId,
      token: p.token,
      agoraUid: p.agoraUid,
      onBattleEnded: widget.onBattleEnded,
    );
  }
}

class _BattlePagePayload {
  const _BattlePagePayload({
    required this.sessionId,
    required this.liveId,
    required this.battleId,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.durationSeconds,
    required this.currentUserId,
    required this.currentUserName,
    required this.channelId,
    required this.token,
    required this.agoraUid,
  });

  final String sessionId;
  final String? liveId;
  final String? battleId;
  final String competitor1Id;
  final String competitor2Id;
  final String competitor1Name;
  final String competitor2Name;
  final String competitor1Type;
  final String competitor2Type;
  final int durationSeconds;
  final String currentUserId;
  final String currentUserName;
  final String channelId;
  final String token;
  final int agoraUid;
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.7)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swipe_vertical_rounded, color: WeAfricaColors.gold, size: 18),
            SizedBox(height: 4),
            Text(
              'Swipe',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
