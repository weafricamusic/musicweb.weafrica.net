import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/app_result.dart';
import '../models/live_session_model.dart';
import '../services/battle_service.dart';
import '../services/live_feed_discover_service.dart';
import '../services/live_session_service.dart';
import 'consumer_battle_screen.dart';
import 'live_watch_screen.dart';

class LiveSwipeWatchScreen extends StatefulWidget {
  const LiveSwipeWatchScreen({
    super.key,
    this.initialChannelId,
  });

  final String? initialChannelId;

  @override
  State<LiveSwipeWatchScreen> createState() => _LiveSwipeWatchScreenState();
}

class _LiveSwipeWatchScreenState extends State<LiveSwipeWatchScreen> {
  final LiveFeedDiscoverService _discoverService = LiveFeedDiscoverService();

  late final PageController _pageController;
  List<Map<String, dynamic>> _streams = const <Map<String, dynamic>>[];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  bool _isBattleRow(Map<String, dynamic> row) {
    final channelId = _s(row['channel_id']).toLowerCase();
    if (channelId.startsWith('weafrica_battle_')) return true;

    final battleId = _s(row['battle_id']);
    if (battleId.isNotEmpty) return true;

    final category = _s(row['category']).toLowerCase();
    if (category == 'battle' || category == 'live_battle' || category == 'battle_1v1') {
      return true;
    }

    final liveType = _s(row['live_type']).toLowerCase();
    if (liveType == 'battle') return true;

    final mode = _s(row['mode']).toLowerCase();
    if (mode.contains('battle')) return true;

    final isBattleFlag = _s(row['is_battle']).toLowerCase();
    return isBattleFlag == 'true' || isBattleFlag == '1';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessions = await _discoverService.fetchLiveNow(limit: 60);
      final visible = sessions.where((m) {
        final text = '${m['host_name']} ${m['host_id']} ${m['channel_id']}'.toLowerCase();
        return !text.contains('phase2') && !text.contains('verify') && !text.contains('post3000');
      }).toList(growable: false);

      if (!mounted) return;

      var initialIndex = 0;
      final initialChannel = _s(widget.initialChannelId);
      if (initialChannel.isNotEmpty) {
        final idx = visible.indexWhere((m) => _s(m['channel_id']) == initialChannel);
        if (idx >= 0) {
          initialIndex = idx;
        }
      }

      setState(() {
        _streams = visible;
        _currentIndex = initialIndex;
        _loading = false;
      });

      if (visible.isNotEmpty && initialIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageController.jumpToPage(initialIndex);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load live streams right now.';
      });
    }
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

    if (_streams.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No live streams right now. Please try again later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _streams.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final row = _streams[index];
              return _LiveSwipePage(
                key: ValueKey(_s(row['channel_id'])),
                row: row,
                isBattle: _isBattleRow(row),
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
                '${_currentIndex + 1}/${_streams.length}',
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

class _LiveSwipePage extends StatefulWidget {
  const _LiveSwipePage({
    super.key,
    required this.row,
    required this.isBattle,
  });

  final Map<String, dynamic> row;
  final bool isBattle;

  @override
  State<_LiveSwipePage> createState() => _LiveSwipePageState();
}

class _LiveSwipePageState extends State<_LiveSwipePage> {
  bool _loading = true;
  String? _error;
  _LiveSwipePayload? _payload;

  String _s(dynamic v) => (v ?? '').toString().trim();

  int _stableAgoraUid(String userId) {
    final h = userId.hashCode.abs();
    final uid = h % 2000000000;
    return uid == 0 ? 1 : uid;
  }

  String _battleIdFromChannel(String channelId) {
    final c = channelId.trim();
    const prefix = 'weafrica_battle_';
    if (!c.startsWith(prefix)) return '';
    return c.substring(prefix.length).trim();
  }

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
      final user = FirebaseAuth.instance.currentUser;
      final viewerId = (user?.uid ?? 'guest').trim();
      final viewerName = _s(user?.displayName).isNotEmpty ? _s(user?.displayName) : 'Viewer';

      final streamId = _s(widget.row['id']);
      final channelId = _s(widget.row['channel_id']);
      final hostId = _s(widget.row['host_id']);
      final hostName = _s(widget.row['host_name']).isNotEmpty ? _s(widget.row['host_name']) : 'Host';

      if (channelId.isEmpty) {
        throw StateError('Missing live channel.');
      }

      final battleIdRaw = _s(widget.row['battle_id']);
      final battleId = battleIdRaw.isNotEmpty ? battleIdRaw : _battleIdFromChannel(channelId);

      final joinRes = await LiveSessionService().joinSession(
        channelId,
        viewerId,
        battleId: widget.isBattle && battleId.isNotEmpty ? battleId : null,
      );
      final session = joinRes.data;
      final joinMessage = switch (joinRes) {
        AppFailure<LiveSession>(:final userMessage) => userMessage,
        _ => null,
      };

      debugPrint(
        'LIVE_SWIPE_JOIN_ATTEMPT channel=$channelId streamId=$streamId viewer=$viewerId isBattle=${widget.isBattle} result=${session == null ? 'failed' : 'ok'} message=${(joinMessage ?? '').trim()}',
      );

      if (session == null) {
        debugPrint('LIVE_SWIPE_JOIN_FAILED row=${widget.row.toString()}');
        throw StateError(
          switch (joinRes) {
            AppFailure<LiveSession>(:final userMessage) =>
              (userMessage ?? '').trim().isEmpty ? 'Could not join this live right now.' : userMessage!,
            _ => 'Could not join this live right now.',
          },
        );
      }

      if (widget.isBattle) {
        final battleRes = await BattleService().getBattle(
          session.id,
          battleId: battleId.isNotEmpty ? battleId : null,
        );
        final battle = battleRes.data;

        if (!mounted) return;
        setState(() {
          _payload = _LiveSwipePayload.battle(
            session: session,
            currentUserId: viewerId,
            currentUserName: viewerName,
            liveId: session.liveId,
            battleId: battle?.id ?? (battleId.isNotEmpty ? battleId : null),
            competitor1Id: battle?.competitor1Id ?? _s(widget.row['host_a_id']),
            competitor2Id: battle?.competitor2Id ?? _s(widget.row['host_b_id']),
            competitor1Name: battle?.competitor1Name ?? hostName,
            competitor2Name: battle?.competitor2Name ?? 'Opponent',
            competitor1Type: battle?.competitor1Type ?? 'artist',
            competitor2Type: battle?.competitor2Type ?? 'artist',
            durationSeconds: battle?.timeRemaining ?? 1800,
            agoraUid: _stableAgoraUid(viewerId),
          );
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _payload = _LiveSwipePayload.solo(
          session: session,
          streamId: streamId,
          hostId: hostId,
          hostName: hostName,
          title: _s(widget.row['title']),
          viewerUid: _stableAgoraUid(viewerId),
        );
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
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final payload = _payload;
    if (payload == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Could not open this live right now.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (payload.isBattle) {
      return ConsumerBattleScreen(
        sessionId: payload.session.id,
        liveId: payload.liveId,
        battleId: payload.battleId,
        competitor1Id: payload.competitor1Id ?? '',
        competitor2Id: payload.competitor2Id ?? '',
        competitor1Name: payload.competitor1Name ?? 'Host A',
        competitor2Name: payload.competitor2Name ?? 'Host B',
        competitor1Type: payload.competitor1Type ?? 'artist',
        competitor2Type: payload.competitor2Type ?? 'artist',
        durationSeconds: payload.durationSeconds ?? 1800,
        currentUserId: payload.currentUserId ?? 'viewer',
        currentUserName: payload.currentUserName ?? 'Viewer',
        channelId: payload.session.channelId,
        token: payload.session.token,
        agoraUid: payload.agoraUid ?? 1,
      );
    }

    return LiveWatchScreen(
      channelId: (payload.streamId ?? payload.streamId ?? "").trim().isNotEmpty
          ? (payload.streamId ?? payload.streamId!)
          : "",
      hostName: (payload.hostName ?? '').trim().isNotEmpty ? payload.hostName! : 'Host',
      streamId: payload.streamId,
    );
  }
}

class _LiveSwipePayload {
  const _LiveSwipePayload._({
    required this.session,
    required this.isBattle,
    this.streamId,
    this.hostId,
    this.hostName,
    this.title,
    this.viewerUid,
    this.liveId,
    this.battleId,
    this.competitor1Id,
    this.competitor2Id,
    this.competitor1Name,
    this.competitor2Name,
    this.competitor1Type,
    this.competitor2Type,
    this.durationSeconds,
    this.currentUserId,
    this.currentUserName,
    this.agoraUid,
  });

  factory _LiveSwipePayload.solo({
    required LiveSession session,
    required String streamId,
    required String hostId,
    required String hostName,
    required String title,
    required int viewerUid,
  }) {
    return _LiveSwipePayload._(
      session: session,
      isBattle: false,
      streamId: streamId,
      hostId: hostId,
      hostName: hostName,
      title: title,
      viewerUid: viewerUid,
    );
  }

  factory _LiveSwipePayload.battle({
    required LiveSession session,
    required String currentUserId,
    required String currentUserName,
    required int agoraUid,
    String? liveId,
    String? battleId,
    String? competitor1Id,
    String? competitor2Id,
    String? competitor1Name,
    String? competitor2Name,
    String? competitor1Type,
    String? competitor2Type,
    int? durationSeconds,
  }) {
    return _LiveSwipePayload._(
      session: session,
      isBattle: true,
      liveId: liveId,
      battleId: battleId,
      competitor1Id: competitor1Id,
      competitor2Id: competitor2Id,
      competitor1Name: competitor1Name,
      competitor2Name: competitor2Name,
      competitor1Type: competitor1Type,
      competitor2Type: competitor2Type,
      durationSeconds: durationSeconds,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      agoraUid: agoraUid,
    );
  }

  final LiveSession session;
  final bool isBattle;

  final String? streamId;
  final String? hostId;
  final String? hostName;
  final String? title;
  final int? viewerUid;

  final String? liveId;
  final String? battleId;
  final String? competitor1Id;
  final String? competitor2Id;
  final String? competitor1Name;
  final String? competitor2Name;
  final String? competitor1Type;
  final String? competitor2Type;
  final int? durationSeconds;
  final String? currentUserId;
  final String? currentUserName;
  final int? agoraUid;
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(Icons.keyboard_arrow_up, color: Colors.white70),
          Text(
            'Swipe up',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          SizedBox(height: 6),
          Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          Text(
            'Swipe down',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
