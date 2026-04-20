import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/app_result.dart';
import '../../app/utils/user_facing_error.dart';
import '../../services/journey_service.dart';
import '../auth/user_role.dart';
import '../pulse/pulse_engagement_repository.dart';
import '../../services/live_priority_access_gate.dart';
import 'models/live_args.dart';
import 'models/live_session_model.dart' as live_model;
import 'screens/consumer_battle_screen.dart';
import 'screens/followers_only_live_gate_screen.dart';
import 'screens/professional_battle_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/live_watch_screen.dart';
import 'screens/solo_live_stream_screen.dart';
import 'services/battle_service.dart';
import 'services/live_session_service.dart';

/// LiveScreen handles both battles and general live feed.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.args});

  final LiveArgs args;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool _loading = true;
  bool _followingToJoin = false;
  String? _error;
  bool _qaBannerExpanded = false;
  late final DateTime _qaBannerTimestamp;

  live_model.LiveSession? _soloSession;
  bool _soloIsBroadcaster = false;

  live_model.LiveSession? _session;
  BattleModelView? _battle;
  String? _resolvedJoinUserIdCache;

  String _currentAuthUserId() {
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  String _resolvedJoinUserId() {
    final cached = _resolvedJoinUserIdCache;
    if (cached != null && cached.isNotEmpty) return cached;

    final authUid = _currentAuthUserId();
    if (authUid.isNotEmpty) {
      _resolvedJoinUserIdCache = authUid;
      return authUid;
    }

    final argsUid = widget.args.hostId?.trim() ?? "";
    if (argsUid.isNotEmpty && argsUid.toLowerCase() != 'guest') {
      _resolvedJoinUserIdCache = argsUid;
      return argsUid;
    }

    final generated = 'viewer_${DateTime.now().microsecondsSinceEpoch}';
    _resolvedJoinUserIdCache = generated;
    return generated;
  }

  @override
  void initState() {
    super.initState();
    _qaBannerTimestamp = DateTime.now();
    if (widget.args.isBattle == true) {
      _loadBattle();
    } else {
      _loadSolo();
    }
  }

  bool _shouldJoinAsBroadcaster(String currentUserId) {
    final uid = currentUserId.trim();
    if (widget.args.role != UserRole.consumer) return true;
    if (uid.isEmpty) return false;
    if (widget.args.battleArtists != null && widget.args.battleArtists!.contains(uid)) return true;
    return false;
  }

  Future<void> _loadSolo() async {
    try {
      final currentUserId = _currentAuthUserId();
      final joinUserId = _resolvedJoinUserId();
      final shouldBroadcast = _shouldJoinAsBroadcaster(currentUserId);

      debugPrint(
        'LiveSession: userId=$joinUserId, role=${widget.args.role?.id ?? 0}, isBroadcaster=$shouldBroadcast, sessionType=solo',
      );

      final res = await LiveSessionService().joinSession(
        widget.args.channelId ?? "",
        joinUserId,
        asBroadcaster: shouldBroadcast,
      );

      var session = res.data;
      String? joinFailureMessage = switch (res) {
        AppFailure<live_model.LiveSession>(:final userMessage) => userMessage,
        _ => null,
      };
      if (session == null &&
          LivePriorityAccessGate.instance.wasBlockedRecently(widget.args.channelId ?? "")) {
        final upgraded = await LivePriorityAccessGate.instance
            .waitForUnblocked(widget.args.channelId ?? "");
        if (upgraded) {
          final retry = await LiveSessionService().joinSession(
            widget.args.channelId ?? "",
            joinUserId,
            asBroadcaster: shouldBroadcast,
          );
          session = retry.data;
          joinFailureMessage = switch (retry) {
            AppFailure<live_model.LiveSession>(:final userMessage) => userMessage,
            _ => joinFailureMessage,
          };
        }
      }

      if (session == null) {
        throw StateError(joinFailureMessage ?? 'Could not join session');
      }

      if (!mounted) return;
      setState(() {
        _soloSession = session;
        _soloIsBroadcaster = shouldBroadcast;
        _loading = false;
      });
    } catch (e, st) {
      UserFacingError.log('LiveScreen._loadSolo', e, st);
      if (!mounted) return;
      final message = UserFacingError.message(
        e,
        fallback: 'Could not open live right now. Please try again.',
      );
      if (_isFollowersOnlyError(message)) {
        _logFollowersOnlyEvent('FOLLOWERS_ONLY_BLOCK');
      }
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _loadBattle() async {
    try {
      final currentUserId = _currentAuthUserId();
      final joinUserId = _resolvedJoinUserId();
      final shouldBroadcast = _shouldJoinAsBroadcaster(currentUserId);

      debugPrint(
        'LiveSession: userId=$joinUserId, role=${widget.args.role?.id ?? 0}, isBroadcaster=$shouldBroadcast, sessionType=battle',
      );

      final res = await LiveSessionService().joinSession(
        widget.args.channelId ?? "",
        joinUserId,
        asBroadcaster: shouldBroadcast,
        battleId: widget.args.battleId,
      );

      var session = res.data;
      String? joinFailureMessage = switch (res) {
        AppFailure<live_model.LiveSession>(:final userMessage) => userMessage,
        _ => null,
      };

      // Priority gate retry
      if (session == null &&
          LivePriorityAccessGate.instance.wasBlockedRecently(widget.args.channelId ?? "")) {
        final upgraded = await LivePriorityAccessGate.instance
            .waitForUnblocked(widget.args.channelId ?? "");
        if (upgraded) {
          final retry = await LiveSessionService().joinSession(
            widget.args.channelId ?? "",
            joinUserId,
            asBroadcaster: shouldBroadcast,
            battleId: widget.args.battleId,
          );
          session = retry.data;
          joinFailureMessage = switch (retry) {
            AppFailure<live_model.LiveSession>(:final userMessage) => userMessage,
            _ => joinFailureMessage,
          };
        }
      }

      if (session == null) {
        throw StateError(joinFailureMessage ?? 'Could not join session');
      }

      // Fetch battle details
      BattleModelView? battle;
      final battleRes = await BattleService().getBattle(
        session.id,
        battleId: widget.args.battleId,
      );
      final b = battleRes.data;
      if (b != null) {
        battle = BattleModelView(
          battleId: b.id,
          competitor1Id: b.competitor1Id,
          competitor2Id: b.competitor2Id,
          competitor1Name: b.competitor1Name,
          competitor2Name: b.competitor2Name,
          competitor1Type: b.competitor1Type,
          competitor2Type: b.competitor2Type,
          durationSeconds: b.timeRemaining > 0 ? b.timeRemaining : 1800,
        );
      }

      if (battle == null) {
        throw StateError('Battle details missing for live session');
      }

      if (!mounted) return;
      setState(() {
        _session = session;
        _battle = battle;
        _loading = false;
      });
    } catch (e, st) {
      UserFacingError.log('LiveScreen._loadBattle', e, st);
      if (!mounted) return;
      final message = UserFacingError.message(
        e,
        fallback: 'Could not open live right now. Please try again.',
      );
      if (_isFollowersOnlyError(message)) {
        _logFollowersOnlyEvent('FOLLOWERS_ONLY_BLOCK');
      }
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  int _stableAgoraUid(String userId) {
    final h = userId.hashCode.abs();
    final uid = (h % 2000000000);
    return uid == 0 ? 1 : uid;
  }

  String _qaTimestampLabel() {
    final t = _qaBannerTimestamp;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  bool _isFollowersOnlyError(String? message) {
    final text = (message ?? '').toLowerCase();
    return text.contains('followers only') || text.contains('followers_only');
  }

  void _logFollowersOnlyEvent(String eventType, {Map<String, Object?>? metadata}) {
    unawaited(
      JourneyService.instance.logEvent(
        eventType: eventType,
        eventKey: widget.args.channelId ?? "",
        metadata: {
          'channel_id': widget.args.channelId ?? "",
          'host_id': widget.args.hostId,
          'is_battle': widget.args.isBattle,
          ...?metadata,
        },
      ),
    );
  }

  Future<void> _followHostAndRetryJoin() async {
    if (_followingToJoin) return;

    final viewerUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final hostId = widget.args.hostId?.trim() ?? "";
    if (viewerUid.isEmpty || hostId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow this creator.')),
      );
      return;
    }

    setState(() {
      _followingToJoin = true;
    });

    try {
      _logFollowersOnlyEvent('FOLLOWERS_ONLY_FOLLOW_CLICK');

      if (kDebugMode) {
        debugPrint('FOLLOWERS_ONLY_FOLLOW_ATTEMPT host=${widget.args.hostId} viewer=$viewerUid');
      }

      await PulseEngagementRepository().setFollow(
        artistId: hostId,
        userId: viewerUid,
        following: true,
      );

      if (kDebugMode) {
        debugPrint('FOLLOWERS_ONLY_FOLLOW_SUCCESS host=${widget.args.hostId} viewer=$viewerUid');
      }

      _logFollowersOnlyEvent('FOLLOWERS_ONLY_FOLLOW_SUCCESS');

      if (!mounted) return;
      setState(() {
        _followingToJoin = false;
        _loading = true;
        _error = null;
      });

      if (widget.args.isBattle == true) {
        await _loadBattle();
      } else {
        await _loadSolo();
      }

      if (kDebugMode) {
        debugPrint('FOLLOWERS_ONLY_RETRY_JOIN_COMPLETE channel=${widget.args.channelId ?? ""}');
      }
      if (!_loading && _error == null) {
        _logFollowersOnlyEvent('FOLLOWERS_ONLY_RETRY_SUCCESS');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _followingToJoin = false;
      });
      if (kDebugMode) {
        debugPrint('FOLLOWERS_ONLY_FOLLOW_FAILED host=${widget.args.hostId} viewer=$viewerUid');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not follow this creator right now.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              unawaited(_followHostAndRetryJoin());
            },
          ),
        ),
      );
    }
  }

  Widget _withQaDebugBanner({
    required Widget child,
    required bool isBroadcaster,
    required String sessionType,
    String? liveId,
    String? battleId,
  }) {
    if (kReleaseMode) return child;

    final branch = '${isBroadcaster ? 'Host' : 'Fan'} ${sessionType == 'battle' ? 'Battle' : 'Solo'}';
    final badgeColor = isBroadcaster
        ? Colors.redAccent.withValues(alpha: 0.74)
        : Colors.lightBlueAccent.withValues(alpha: 0.74);
    final details = <String>[
      branch,
      'role=${widget.args.role?.id ?? 0}',
      'session=$sessionType',
      if ((liveId ?? '').trim().isNotEmpty) 'live=${liveId!.trim()}',
      if ((battleId ?? '').trim().isNotEmpty) 'battle=${battleId!.trim()}',
      'at=${_qaTimestampLabel()}',
    ].join('  •  ');

    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 16,
          right: 12,
          child: SafeArea(
            child: GestureDetector(
              onTap: () => setState(() => _qaBannerExpanded = !_qaBannerExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _qaBannerExpanded ? 10 : 8,
                    vertical: _qaBannerExpanded ? 7 : 5,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: _qaBannerExpanded ? 330 : 170),
                    child: Text(
                      _qaBannerExpanded ? details : branch,
                      maxLines: _qaBannerExpanded ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
 
    }

    final err = _error;
    if (err != null) {
      final followersOnly = _isFollowersOnlyError(err);
      if (followersOnly) {
        return FollowersOnlyLiveGateScreen(
          hostName: widget.args.hostName ?? "",
          message: err,
          isLoading: _followingToJoin,
          onFollowJoin: _followHostAndRetryJoin,
          onBack: () => Navigator.of(context).pop(),
        );
      }

      return Scaffold(
        appBar: AppBar(title: const Text('Live')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(err, style: const TextStyle(color: AppColors.textMuted)),
          ),
        ),
      );
    }

    if (widget.args.isBattle != true) {
      final session = _soloSession;
      if (session == null) {
        return const LiveFeedScreen();
      }

      final currentUserId = _currentAuthUserId();
      final viewerId = currentUserId.isNotEmpty ? currentUserId : _resolvedJoinUserId();
      final hostName = (widget.args.hostName ?? "").trim().isEmpty
          ? (session.hostName.trim().isEmpty ? 'Host' : session.hostName.trim())
          : widget.args.hostName ?? "".trim();

      if (_soloIsBroadcaster) {
        return _withQaDebugBanner(
          child: SoloLiveStreamScreen(
            title: session.title,
            hostName: hostName,
            channelId: session.channelId,
            token: session.token,
            liveStreamId: session.liveId,
          ),
          isBroadcaster: true,
          sessionType: 'solo',
          liveId: session.liveId ?? widget.args.liveId,
        );

      }

      return _withQaDebugBanner(
        isBroadcaster: false,
        sessionType: 'solo',
        liveId: session.liveId ?? widget.args.liveId,
        child: LiveWatchScreen(
          channelId: (session.liveId ?? widget.args.liveId ?? "").trim().isNotEmpty
              ? (session.liveId ?? widget.args.liveId!)
              : "",
          hostName: hostName,
          streamId: session.liveId,
        ),
      );
    }

    final session = _session;
    final battle = _battle;
    if (session == null || battle == null) {
      return const LiveFeedScreen();
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final currentUserId = _currentAuthUserId();
    final effectiveUserId = currentUserId.isNotEmpty ? currentUserId : _resolvedJoinUserId();
    final currentUserName = (firebaseUser?.displayName ?? widget.args.hostName ?? "").trim();

    final isBroadcaster = _shouldJoinAsBroadcaster(currentUserId);

    if (session.token.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Connection issue. Please rejoin')),
      );
    }

    if (isBroadcaster) {
      return _withQaDebugBanner(
        isBroadcaster: true,
        sessionType: 'battle',
        liveId: session.liveId,
        battleId: widget.args.battleId,
        child: ProfessionalBattleScreen(
          sessionId: session.id,
          liveId: session.liveId,
          battleId: widget.args.battleId,
          competitor1Id: battle.competitor1Id,
          competitor2Id: battle.competitor2Id,
          competitor1Name: battle.competitor1Name,
          competitor2Name: battle.competitor2Name,
          competitor1Type: battle.competitor1Type,
          competitor2Type: battle.competitor2Type,
          durationSeconds: battle.durationSeconds,
          currentUserId: effectiveUserId,
          currentUserName: currentUserName.isNotEmpty ? currentUserName : 'You',
          channelId: session.channelId,
          token: session.token,
          agoraUid: _stableAgoraUid(effectiveUserId),
        ),
      );
    } else {
      return _withQaDebugBanner(
        isBroadcaster: false,
        sessionType: 'battle',
        liveId: session.liveId,
        battleId: widget.args.battleId,
        child: ConsumerBattleScreen(
          sessionId: session.id,
          liveId: session.liveId,
          battleId: widget.args.battleId,
          competitor1Id: battle.competitor1Id,
          competitor2Id: battle.competitor2Id,
          competitor1Name: battle.competitor1Name,
          competitor2Name: battle.competitor2Name,
          competitor1Type: battle.competitor1Type,
          competitor2Type: battle.competitor2Type,
          durationSeconds: battle.durationSeconds,
          currentUserId: effectiveUserId,
          currentUserName: currentUserName.isNotEmpty ? currentUserName : 'Viewer',
          channelId: session.channelId,
          token: session.token,
          agoraUid: _stableAgoraUid(effectiveUserId),
        ),
      );
    }
  }
}

/// Battle model for UI
class BattleModelView {
  const BattleModelView({
    required this.battleId,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.durationSeconds,
  });

  final String battleId;
  final String competitor1Id;
  final String competitor2Id;
  final String competitor1Name;
  final String competitor2Name;
  final String competitor1Type;
  final String competitor2Type;
  final int durationSeconds;
}