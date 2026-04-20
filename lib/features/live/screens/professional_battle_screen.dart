import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../../app/utils/app_result.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/widgets/gold_button.dart';
import '../controllers/battle_controller.dart';
import '../controllers/gift_controller.dart';
import '../controllers/live_stream_controller.dart';
import '../models/beat_model.dart';
import '../models/battle_status.dart';
import '../models/chat_message_model.dart';
import '../models/gift_model.dart';
import '../models/live_session_model.dart';
import '../services/battle_host_api.dart';
import '../services/battle_interactions_service.dart';
import '../services/battle_status_service.dart';
import '../services/beat_service.dart';
import '../services/chat_service.dart';
import '../services/gift_service.dart';
import '../services/live_realtime_service.dart';
import '../services/live_session_service.dart';
import '../widgets/battle/battle_invite_dialog.dart';
import '../widgets/battle/battle_split_view.dart';
import '../widgets/beat_selection_widget.dart';
import '../widgets/gift/gift_animation_overlay.dart';
import '../widgets/gift/gift_selection_sheet.dart';
import '../../beats/services/beat_download_service.dart';

class ProfessionalBattleScreen extends StatefulWidget {
  const ProfessionalBattleScreen({
    super.key,
    required this.sessionId,
    this.liveId,
    this.battleId,
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
    this.competitor1AvatarUrl,
    this.competitor2AvatarUrl,
    this.autoPromptInviteOnStart = false,
    this.initialBeatId,
    this.initialBeatName,
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
  final String? competitor1AvatarUrl;
  final String? competitor2AvatarUrl;
  final bool autoPromptInviteOnStart;

  /// Optional beat to auto-play for the host once the stream is connected.
  final String? initialBeatId;
  final String? initialBeatName;

  @override
  State<ProfessionalBattleScreen> createState() =>
      _ProfessionalBattleScreenState();
}

class _ProfessionalBattleScreenState extends State<ProfessionalBattleScreen>
    with WidgetsBindingObserver {
  static const int _transitionBufferSeconds = 8;

  late final LiveStreamController _streamController;
  late final BattleController _battleController;
  late final GiftController _giftController;
  late final LiveRealtimeService _realtimeService;

  StreamSubscription<int>? _viewerCountSub;
  StreamSubscription<Map<String, int>>? _scoreSub;
  StreamSubscription<GiftModel>? _giftSub;
  StreamSubscription<dynamic>? _connectivitySub;
  Timer? _heartbeatTimer;
  Timer? _battleStatusTimer;
  Timer? _reactionThrottle;
  Timer? _timelineTick;

  bool _isLoading = true;
  bool _endingLive = false;
  bool _isOffline = false;
  bool _winnerShown = false;
  String? _error;

  int _viewerCount = 0;
  int _totalSpentCoins = 0;
  int? _coinGoal;
  String? _battleStatus;
  String? _resolvedOpponentId;
  String? _resolvedOpponentName;
  String? _competitor1AvatarUrl;
  String? _competitor2AvatarUrl;
  bool _didAutoPromptInvite = false;
  String? _selectedBeatId;
  bool _hostBoostEnabled = false;
  bool _hostControlBusy = false;
  String? _overrideCompetitor2Id;
  String? _overrideCompetitor2Name;
  bool _forceCompetitor2Cleared = false;

  BattleStatus? _lastBattleStatus;
  bool? _timelineMicEnabled;
  bool _manualMicMuted = false;

  _BattleTimelinePhase? _lastTimelinePhaseSeen;
  bool _transitionPauseInFlight = false;
  int _transitionPauseToken = 0;
  DateTime? _transitionPausedAt;

  bool _performerMode = false;
  bool _performerModeLoaded = false;
  bool _hostCommentsVisible = true;
  bool _localVideoEnabled = true;
  bool _djDeckPlaying = false;
  bool _djReverbEnabled = false;
  bool _djEchoEnabled = false;
  double _djMasterVolume = 0.78;
  double _djMicVolume = 0.72;
  final List<BeatModel> _djQueue = <BeatModel>[];
  int _djQueueIndex = -1;
  String _selectedBeatName = '';

  final List<FloatingHeart> _floatingHearts = <FloatingHeart>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _competitor1AvatarUrl = _normalizeAvatar(widget.competitor1AvatarUrl);
    _competitor2AvatarUrl = _normalizeAvatar(widget.competitor2AvatarUrl);
    final initialBeatId = (widget.initialBeatId ?? '').trim();
    _selectedBeatId = initialBeatId.isEmpty ? null : initialBeatId;
    _selectedBeatName = (widget.initialBeatName ?? '').trim();
    _overrideCompetitor2Id = widget.competitor2Id.trim().isEmpty ? null : widget.competitor2Id.trim();
    _overrideCompetitor2Name = widget.competitor2Name.trim().isEmpty ? null : widget.competitor2Name.trim();

    _streamController = LiveStreamController();
    _battleController = BattleController(
      durationSeconds: widget.durationSeconds,
      onBattleEnd: _handleBattleEnded,
    );
    _giftController = GiftController();
    _realtimeService = LiveRealtimeService(
      channelId: widget.channelId,
      competitor1Id: widget.competitor1Id,
      competitor2Id: widget.competitor2Id,
    );

    _monitorConnectivity();
    unawaited(_initialize());

    final battleId = _effectiveBattleId();
    if (battleId != null && battleId.isNotEmpty) {
      unawaited(_refreshBattleStatus());
      _battleStatusTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_refreshBattleStatus()),
      );

      _timelineTick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickTimeline(),
      );
    }

    if (_resolveUserRole() == UserRole.host) {
      unawaited(LiveSessionService().heartbeat(channelId: widget.channelId));
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(
          LiveSessionService().heartbeat(channelId: widget.channelId),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_didAutoPromptInvite) return;
      if (!widget.autoPromptInviteOnStart) return;
      if (_resolveUserRole() != UserRole.host) return;
      if (!_isWaitingForOpponent) return;
      _didAutoPromptInvite = true;
      unawaited(_inviteOpponentToExistingBattle());
    });

    unawaited(_loadCompetitorAvatarsIfNeeded());
    unawaited(_loadPerformerModePreference());
    unawaited(_loadDjQueueIfNeeded());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _resolveUserRole() == UserRole.host &&
        !_endingLive &&
        _heartbeatTimer == null) {
      unawaited(LiveSessionService().heartbeat(channelId: widget.channelId));
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(
          LiveSessionService().heartbeat(channelId: widget.channelId),
        ),
      );
    }

    if (state == AppLifecycleState.resumed) {
      _tickTimeline(force: true);
    }
  }

  void _monitorConnectivity() {
    unawaited(() async {
      try {
        final dynamic initial = await Connectivity().checkConnectivity();
        if (!mounted) return;
        setState(() => _isOffline = !_isConnectedResult(initial));
      } catch (_) {}
    }());

    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final connected = _isConnectedResult(result);
      final wasOffline = _isOffline;
      if (!mounted) return;
      setState(() => _isOffline = !connected);
      if (wasOffline && connected) {
        unawaited(_reconnectServices());
      }
    });
  }

  bool _isConnectedResult(dynamic result) {
    if (result is ConnectivityResult) return result != ConnectivityResult.none;
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }
    return true;
  }

  Future<void> _reconnectServices() async {
    try {
      await _realtimeService.disconnect();
      await _realtimeService.connect();
      _subscribeToRealtime();
      if (_resolveUserRole() == UserRole.host) {
        await LiveSessionService().heartbeat(channelId: widget.channelId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconnected to battle room.'),
          backgroundColor: WeAfricaColors.success,
        ),
      );
    } catch (_) {}
  }

  Future<void> _initialize() async {
    try {
      final role = _resolveUserRole();
      final initialized = await _streamController.initialize(
        channelId: widget.channelId,
        token: widget.token,
        role: role,
        uid: widget.agoraUid,
      );
      if (!initialized) {
        throw StateError('Stream initialization failed');
      }

      await _realtimeService.connect();
      _subscribeToRealtime();

      final battleId = _effectiveBattleId();
      if (battleId != null && battleId.isNotEmpty) {
        await _battleController.connectToBattle(battleId);
      } else {
        _battleController.startLocalCountdown();
      }

      if (_shouldPublishBeat && (_selectedBeatId ?? '').trim().isNotEmpty) {
        unawaited(_startSelectedBeatMixing());
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._initialize', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load battle session.';
        _isLoading = false;
      });
    }
  }

  void _subscribeToRealtime() {
    unawaited(_viewerCountSub?.cancel() ?? Future<void>.value());
    unawaited(_scoreSub?.cancel() ?? Future<void>.value());
    unawaited(_giftSub?.cancel() ?? Future<void>.value());

    _viewerCountSub = _realtimeService.viewerCountStream.listen((count) {
      if (!mounted) return;
      setState(() => _viewerCount = count);
    });

    _scoreSub = _realtimeService.scoreStream.listen((scores) {
      _battleController.applyRealtimeScores(scores);
    });

    _giftSub = _realtimeService.giftStream.listen((gift) {
      if (!mounted) return;
      _giftController.receiveGift(gift);
    });
  }

  UserRole _resolveUserRole() {
    final me = widget.currentUserId.trim();
    if (me.isEmpty) return UserRole.audience;
    if (me == widget.competitor1Id.trim()) return UserRole.host;
    if (me == widget.competitor2Id.trim()) return UserRole.opponent;
    return UserRole.audience;
  }

  String? _normalizeAvatar(String? url) {
    final value = (url ?? '').trim();
    return value.isEmpty ? null : value;
  }

  String? _effectiveBattleId() {
    final explicit = (widget.battleId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    const prefix = 'weafrica_battle_';
    final channelId = widget.channelId.trim();
    if (channelId.startsWith(prefix)) {
      final derived = channelId.substring(prefix.length).trim();
      return derived.isEmpty ? null : derived;
    }
    return null;
  }

  String get _effectiveCompetitor2Id {
    if (_forceCompetitor2Cleared) return '';
    final override = (_overrideCompetitor2Id ?? '').trim();
    if (override.isNotEmpty) return override;
    final explicit = widget.competitor2Id.trim();
    if (explicit.isNotEmpty) return explicit;
    return (_resolvedOpponentId ?? '').trim();
  }

  String get _effectiveCompetitor2Name {
    if (_forceCompetitor2Cleared) return 'Opponent';
    final override = (_overrideCompetitor2Name ?? '').trim();
    if (override.isNotEmpty) return override;
    final explicit = widget.competitor2Name.trim();
    if (explicit.isNotEmpty) return explicit;
    final resolved = (_resolvedOpponentName ?? '').trim();
    return resolved.isNotEmpty ? resolved : 'Opponent';
  }

  int _stableAgoraUid(String userId) {
    final hash = userId.hashCode.abs() % 2000000000;
    return hash == 0 ? 1 : hash;
  }

  bool _opponentIsConnected(Set<int> remoteVideoUids) {
    final opponentId = _effectiveCompetitor2Id;
    if (opponentId.isEmpty) return remoteVideoUids.isNotEmpty;
    return remoteVideoUids.contains(_stableAgoraUid(opponentId));
  }

  bool get _isWaitingForOpponent {
    final status = (_battleStatus ?? '').trim().toLowerCase();
    if (_resolveUserRole() != UserRole.host) return false;
    if ((_effectiveBattleId() ?? '').isEmpty) return false;
    if (status == 'ended') return false;
    return !_opponentIsConnected(_streamController.remoteVideoUids);
  }

  String _currentUserCreatorType() {
    final role = _resolveUserRole();
    if (role == UserRole.host) return widget.competitor1Type.trim().toLowerCase();
    if (role == UserRole.opponent) return widget.competitor2Type.trim().toLowerCase();
    return '';
  }

  bool get _isDjPerformer {
    final role = _resolveUserRole();
    if (role != UserRole.host && role != UserRole.opponent) return false;
    final type = _currentUserCreatorType();
    return type == 'dj' || type.contains('dj');
  }

  bool get _shouldPublishBeat {
    if (kIsWeb) return false;
    return _resolveUserRole() == UserRole.host;
  }

  Future<void> _startSelectedBeatMixing() async {
    if (!_shouldPublishBeat) return;

    final beatId = (_selectedBeatId ?? '').trim();
    if (beatId.isEmpty) return;

    try {
      BeatModel? beat;
      for (final queued in _djQueue) {
        if (queued.id == beatId) {
          beat = queued;
          break;
        }
      }

      beat ??= await BeatService().getBeatById(beatId);
      if (beat == null) return;

      final audioUrl = await beat.resolveAudioUrl(Supabase.instance.client);
      if (audioUrl == null || audioUrl.trim().isEmpty) return;

      final filePath = await BeatDownloadService().downloadMp3(
        url: audioUrl,
        fileNameStem: 'battle_${beat.id}',
      );

      final publishVolume = (45 * _djMasterVolume).round().clamp(15, 80);
      final playoutVolume = (60 * _djMasterVolume).round().clamp(20, 100);

      final ok = await _streamController.startBackgroundBeat(
        filePath: filePath,
        publishVolumePercent: publishVolume,
        playoutVolumePercent: playoutVolume,
        loop: true,
      );

      if (!mounted) return;
      if (ok) {
        setState(() {
          _djDeckPlaying = true;
          if (_selectedBeatName.isEmpty) {
            _selectedBeatName = beat!.name;
          }
        });
      }
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._startSelectedBeatMixing', e, st);
    }
  }

  Future<void> _pauseBeatMixing() async {
    if (!_shouldPublishBeat) return;
    await _streamController.pauseBackgroundBeat();
    if (!mounted) return;
    setState(() => _djDeckPlaying = false);
  }

  Future<void> _resumeBeatMixing() async {
    if (!_shouldPublishBeat) return;

    if ((_streamController.backgroundBeatFilePath ?? '').trim().isNotEmpty) {
      await _streamController.resumeBackgroundBeat();
      if (!mounted) return;
      setState(() => _djDeckPlaying = true);
      return;
    }

    await _startSelectedBeatMixing();
  }

  Future<void> _loadDjQueueIfNeeded() async {
    if (!_isDjPerformer) return;
    if (_djQueue.isNotEmpty) return;

    try {
      final beats = await BeatService().getAvailableBeats();
      if (!mounted || beats.isEmpty) return;
      setState(() {
        _djQueue
          ..clear()
          ..addAll(beats.take(8));
        _djQueueIndex = 0;
        _selectedBeatId ??= _djQueue.first.id;
        if (_selectedBeatName.trim().isEmpty) {
          _selectedBeatName = _djQueue.first.name;
        }
      });
    } catch (_) {
      // Best-effort: UI still works without queue preload.
    }
  }

  void _toggleDjPlaybackTap() {
    unawaited(_toggleDjPlayback());
  }

  Future<void> _toggleDjPlayback() async {
    if (!_shouldPublishBeat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the host can publish the battle beat.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    if (_djDeckPlaying) {
      await _pauseBeatMixing();
    } else {
      await _resumeBeatMixing();
    }
  }

  void _skipDjTrack() {
    if (_djQueue.isEmpty) return;
    setState(() {
      _djQueueIndex = (_djQueueIndex + 1) % _djQueue.length;
      final beat = _djQueue[_djQueueIndex];
      _selectedBeatId = beat.id;
      _selectedBeatName = beat.name;
    });
    unawaited(_persistBattlePatch(<String, Object?>{'beat_name': _selectedBeatName}));
    if (_djDeckPlaying) {
      unawaited(_startSelectedBeatMixing());
    }
  }

  Future<void> _refreshBattleStatus() async {
    final battleId = _effectiveBattleId();
    if (battleId == null || battleId.isEmpty) return;
    final res = await BattleStatusService().fetchStatus(battleId: battleId);
    final status = res.data;
    if (status == null || !mounted) return;

    setState(() {
      _battleStatus = status.status.trim();
      _coinGoal = status.coinGoal;
      _totalSpentCoins = status.totalSpentCoins ?? _totalSpentCoins;
      _hostBoostEnabled = status.crowdBoostEnabled;
      _lastBattleStatus = status;
    });

    _tickTimeline(force: true);

    final opponentId = status.hostBId.trim();
    if (opponentId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _forceCompetitor2Cleared = true;
        _overrideCompetitor2Id = null;
        _overrideCompetitor2Name = null;
        _resolvedOpponentId = null;
        _resolvedOpponentName = null;
        _competitor2AvatarUrl = null;
      });
      return;
    }

    if (opponentId != (_resolvedOpponentId ?? '').trim() || opponentId != (_overrideCompetitor2Id ?? '').trim()) {
      _resolvedOpponentId = opponentId;
      await _realtimeService.setCompetitor2Id(opponentId);
      await _loadResolvedOpponentProfileIfNeeded(opponentId);
    }
  }

  void _tickTimeline({bool force = false}) {
    if (!mounted) return;

    final status = _lastBattleStatus;
    if (status == null) {
      if (force) {
        setState(() {});
      }
      return;
    }

    final snapshot = _computeTimelineSnapshot(status);
    if (snapshot == null) {
      if (force) {
        setState(() {});
      }
      return;
    }

    final previousPhase = _lastTimelinePhaseSeen;
    _lastTimelinePhaseSeen = snapshot.phase;
    if (_resolveUserRole() == UserRole.host) {
      unawaited(_maybeApplyTransitionBuffer(previousPhase, snapshot, status));
    }

    // Always repaint once a second for the countdown.
    setState(() {});
    unawaited(_applyTimelineMicEnforcement(snapshot));
  }

  _BattleTimelineSnapshot? _computeTimelineSnapshot(BattleStatus status) {
    final st = status.status.trim().toLowerCase();
    if (st != 'live') return null;

    // If there is no opponent slot yet, do not enforce turns.
    if (status.hostBId.trim().isEmpty) return null;

    final now = DateTime.now().toUtc();
    final effectiveNow = status.timelinePausedAt ?? now;

    final anchorAt = status.timelineAnchorAt ?? status.startedAt;
    if (anchorAt == null) return null;

    final delta = effectiveNow.difference(anchorAt).inSeconds;
    final elapsed = (status.timelineAnchorElapsedSeconds + (delta > 0 ? delta : 0)).clamp(0, 1 << 30);

    final perfA = status.timelinePerfASeconds.clamp(0, 1 << 20);
    final perfB = status.timelinePerfBSeconds.clamp(0, 1 << 20);
    final judging = status.timelineJudgingSeconds.clamp(0, 1 << 20);
    final total = perfA + perfB + judging;

    if (total <= 0) {
      return _BattleTimelineSnapshot(
        phase: _BattleTimelinePhase.notStarted,
        remainingSecondsInPhase: 0,
        elapsedSeconds: elapsed,
        isPaused: status.timelinePausedAt != null,
        perfASeconds: perfA,
        perfBSeconds: perfB,
        judgingSeconds: judging,
      );
    }

    if (elapsed < perfA) {
      return _BattleTimelineSnapshot(
        phase: _BattleTimelinePhase.performerA,
        remainingSecondsInPhase: perfA - elapsed,
        elapsedSeconds: elapsed,
        isPaused: status.timelinePausedAt != null,
        perfASeconds: perfA,
        perfBSeconds: perfB,
        judgingSeconds: judging,
      );
    }

    if (elapsed < perfA + perfB) {
      return _BattleTimelineSnapshot(
        phase: _BattleTimelinePhase.performerB,
        remainingSecondsInPhase: (perfA + perfB) - elapsed,
        elapsedSeconds: elapsed,
        isPaused: status.timelinePausedAt != null,
        perfASeconds: perfA,
        perfBSeconds: perfB,
        judgingSeconds: judging,
      );
    }

    if (elapsed < perfA + perfB + judging) {
      return _BattleTimelineSnapshot(
        phase: _BattleTimelinePhase.judging,
        remainingSecondsInPhase: (perfA + perfB + judging) - elapsed,
        elapsedSeconds: elapsed,
        isPaused: status.timelinePausedAt != null,
        perfASeconds: perfA,
        perfBSeconds: perfB,
        judgingSeconds: judging,
      );
    }

    return _BattleTimelineSnapshot(
      phase: _BattleTimelinePhase.complete,
      remainingSecondsInPhase: 0,
      elapsedSeconds: elapsed,
      isPaused: status.timelinePausedAt != null,
      perfASeconds: perfA,
      perfBSeconds: perfB,
      judgingSeconds: judging,
    );
  }

  Future<void> _applyTimelineMicEnforcement(_BattleTimelineSnapshot snapshot) async {
    final role = _resolveUserRole();
    if (role == UserRole.audience) return;

    final status = _lastBattleStatus;
    if (status == null) return;

    final engine = _streamController.engine;
    if (engine == null) return;

    final isHost = role == UserRole.host;
    final isTransitionPause = _isTransitionPauseSnapshot(status, snapshot);
    final timelineAllowsMic = switch (snapshot.phase) {
      _BattleTimelinePhase.performerA => isTransitionPause ? false : isHost,
      _BattleTimelinePhase.performerB => isTransitionPause ? false : !isHost,
      _ => false,
    };
    final shouldEnable = timelineAllowsMic && !_manualMicMuted;

    if (_timelineMicEnabled == shouldEnable) return;

    try {
      await engine.enableLocalAudio(shouldEnable);
      _timelineMicEnabled = shouldEnable;
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _toggleManualMicMute() async {
    final role = _resolveUserRole();
    if (role == UserRole.audience) return;

    if (!mounted) return;
    setState(() => _manualMicMuted = !_manualMicMuted);

    final status = _lastBattleStatus;
    if (status == null) return;
    final snapshot = _computeTimelineSnapshot(status);
    if (snapshot == null) return;
    await _applyTimelineMicEnforcement(snapshot);
  }

  Future<void> _switchCameraLens() async {
    final engine = _streamController.engine;
    if (engine == null) return;
    try {
      await engine.switchCamera();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not switch camera.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  Future<void> _toggleLocalVideo() async {
    final engine = _streamController.engine;
    if (engine == null) return;

    final nextEnabled = !_localVideoEnabled;
    try {
      await engine.muteLocalVideoStream(!nextEnabled);
      if (!mounted) return;
      setState(() => _localVideoEnabled = nextEnabled);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not toggle camera video.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  bool _isTransitionPauseSnapshot(BattleStatus status, _BattleTimelineSnapshot snapshot) {
    if (!snapshot.isPaused) return false;
    final pausedAt = status.timelinePausedAt;
    if (pausedAt == null) return false;

    // Treat a pause exactly at the start of the next phase as a "transition buffer".
    if (snapshot.phase == _BattleTimelinePhase.performerB && snapshot.remainingSecondsInPhase == snapshot.perfBSeconds) {
      return true;
    }
    if (snapshot.phase == _BattleTimelinePhase.judging && snapshot.remainingSecondsInPhase == snapshot.judgingSeconds) {
      return true;
    }
    return false;
  }

  Future<void> _maybeApplyTransitionBuffer(
    _BattleTimelinePhase? previous,
    _BattleTimelineSnapshot current,
    BattleStatus status,
  ) async {
    if (_transitionBufferSeconds <= 0) return;
    if (_transitionPauseInFlight) return;
    if (status.timelinePausedAt != null) return;

    // Only apply buffers once an opponent is actually present.
    if (status.hostBId.trim().isEmpty) return;

    final boundaryElapsed = switch (current.phase) {
      _BattleTimelinePhase.performerB when previous == _BattleTimelinePhase.performerA => current.perfASeconds,
      _BattleTimelinePhase.judging when previous == _BattleTimelinePhase.performerB => current.perfASeconds + current.perfBSeconds,
      _ => null,
    };
    if (boundaryElapsed == null) return;

    // Avoid drift: only buffer at (or within 1s of) the start of the phase.
    if (current.phase == _BattleTimelinePhase.performerB && current.remainingSecondsInPhase < (current.perfBSeconds - 1)) return;
    if (current.phase == _BattleTimelinePhase.judging && current.remainingSecondsInPhase < (current.judgingSeconds - 1)) return;

    await _pauseTimelineForTransition(boundaryElapsedSeconds: boundaryElapsed, seconds: _transitionBufferSeconds);
  }

  Future<void> _pauseTimelineForTransition({
    required int boundaryElapsedSeconds,
    required int seconds,
  }) async {
    if (_resolveUserRole() != UserRole.host) return;
    if (seconds <= 0) return;
    if (_transitionPauseInFlight) return;

    final token = ++_transitionPauseToken;
    final pausedAt = DateTime.now().toUtc();
    _transitionPausedAt = pausedAt;

    _transitionPauseInFlight = true;
    try {
      await _persistBattlePatch(<String, Object?>{
        'timeline_anchor_at': pausedAt.toIso8601String(),
        'timeline_anchor_elapsed_seconds': boundaryElapsedSeconds,
        'timeline_paused_at': pausedAt.toIso8601String(),
      });
      unawaited(_refreshBattleStatus());
    } catch (_) {
      // Best-effort.
    } finally {
      _transitionPauseInFlight = false;
    }

    Future.delayed(Duration(seconds: seconds), () async {
      if (!mounted) return;
      if (_resolveUserRole() != UserRole.host) return;
      if (token != _transitionPauseToken) return;

      final st = _lastBattleStatus;
      if (st == null) return;
      final stillPausedAt = st.timelinePausedAt;
      if (stillPausedAt == null) return;
      final expectedPausedAt = _transitionPausedAt;
      if (expectedPausedAt == null) return;
      if (stillPausedAt.difference(expectedPausedAt).inSeconds != 0) return;

      final now = DateTime.now().toUtc();
      try {
        await _persistBattlePatch(<String, Object?>{
          'timeline_anchor_at': now.toIso8601String(),
          'timeline_anchor_elapsed_seconds': boundaryElapsedSeconds,
          'timeline_paused_at': null,
        });
        unawaited(_refreshBattleStatus());
      } catch (_) {
        // Best-effort.
      }
    });
  }

  int _transitionCountdownSeconds(BattleStatus status, _BattleTimelineSnapshot snapshot) {
    if (!_isTransitionPauseSnapshot(status, snapshot)) return 0;
    final pausedAt = status.timelinePausedAt;
    if (pausedAt == null) return 0;

    final elapsed = DateTime.now().toUtc().difference(pausedAt).inSeconds;
    final remaining = _transitionBufferSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _ensureTimelineInitializedIfNeeded() async {
    if (_resolveUserRole() != UserRole.host) return;
    final status = _lastBattleStatus;
    if (status == null) return;
    if (status.timelineAnchorAt != null || status.startedAt != null) return;

    // If started_at wasn't persisted for some reason, anchor to now.
    try {
      await _persistBattlePatch(<String, Object?>{
        'timeline_anchor_at': DateTime.now().toUtc().toIso8601String(),
        'timeline_anchor_elapsed_seconds': 0,
        'timeline_paused_at': null,
      });
      await _refreshBattleStatus();
    } catch (_) {}
  }

  Future<void> _toggleTimelinePause() async {
    if (_resolveUserRole() != UserRole.host) return;
    if (_hostControlBusy) return;

    final status = _lastBattleStatus;
    if (status == null) return;
    final snapshot = _computeTimelineSnapshot(status);
    if (snapshot == null) return;

    setState(() => _hostControlBusy = true);
    try {
      final now = DateTime.now().toUtc();
      final pausedAt = status.timelinePausedAt;

      if (pausedAt == null) {
        await _persistBattlePatch(<String, Object?>{
          'timeline_paused_at': now.toIso8601String(),
        });
      } else {
        final anchorAt = status.timelineAnchorAt ?? status.startedAt;
        if (anchorAt == null) {
          await _persistBattlePatch(<String, Object?>{
            'timeline_anchor_at': now.toIso8601String(),
            'timeline_anchor_elapsed_seconds': status.timelineAnchorElapsedSeconds,
            'timeline_paused_at': null,
          });
        } else {
          final frozenDelta = pausedAt.difference(anchorAt).inSeconds;
          final nextElapsed = (status.timelineAnchorElapsedSeconds + (frozenDelta > 0 ? frozenDelta : 0)).clamp(0, 1 << 30);
          await _persistBattlePatch(<String, Object?>{
            'timeline_anchor_at': now.toIso8601String(),
            'timeline_anchor_elapsed_seconds': nextElapsed,
            'timeline_paused_at': null,
          });
        }
      }

      await _refreshBattleStatus();
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._toggleTimelinePause', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, fallback: 'Could not update the battle timer right now.')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _hostControlBusy = false);
      }
    }
  }

  Future<void> _skipToNextPhase() async {
    if (_resolveUserRole() != UserRole.host) return;
    if (_hostControlBusy) return;

    final status = _lastBattleStatus;
    if (status == null) return;
    final snapshot = _computeTimelineSnapshot(status);
    if (snapshot == null) return;

    final perfA = snapshot.perfASeconds;
    final perfB = snapshot.perfBSeconds;
    final judging = snapshot.judgingSeconds;
    final boundary = switch (snapshot.phase) {
      _BattleTimelinePhase.performerA => perfA,
      _BattleTimelinePhase.performerB => perfA + perfB,
      _BattleTimelinePhase.judging => perfA + perfB + judging,
      _ => null,
    };
    if (boundary == null) return;

    setState(() => _hostControlBusy = true);
    try {
      final now = DateTime.now().toUtc();
      final pausedAt = status.timelinePausedAt;

      if (pausedAt != null) {
        await _persistBattlePatch(<String, Object?>{
          'timeline_anchor_at': pausedAt.toIso8601String(),
          'timeline_anchor_elapsed_seconds': boundary,
          'timeline_paused_at': pausedAt.toIso8601String(),
        });
      } else {
        await _persistBattlePatch(<String, Object?>{
          'timeline_anchor_at': now.toIso8601String(),
          'timeline_anchor_elapsed_seconds': boundary,
          'timeline_paused_at': null,
        });
      }

      await _refreshBattleStatus();
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._skipToNextPhase', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, fallback: 'Could not switch turns right now.')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _hostControlBusy = false);
      }
    }
  }

  Future<void> _loadCompetitorAvatarsIfNeeded() async {
    if (_competitor1AvatarUrl != null && _competitor2AvatarUrl != null) return;
    final ids = <String>[];
    if (_competitor1AvatarUrl == null && widget.competitor1Id.trim().isNotEmpty) {
      ids.add(widget.competitor1Id.trim());
    }
    if (_competitor2AvatarUrl == null && _effectiveCompetitor2Id.isNotEmpty) {
      ids.add(_effectiveCompetitor2Id);
    }
    if (ids.isEmpty) return;

    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, avatar_url')
          .inFilter('id', ids);
      if (!mounted) return;
      final found = <String, String>{};
      for (final raw in (rows as List).whereType<Map>()) {
        final id = (raw['id'] ?? '').toString().trim();
        final avatar = (raw['avatar_url'] ?? '').toString().trim();
        if (id.isEmpty || avatar.isEmpty) continue;
        found[id] = avatar;
      }
      setState(() {
        _competitor1AvatarUrl ??= found[widget.competitor1Id.trim()];
        _competitor2AvatarUrl ??= found[_effectiveCompetitor2Id];
      });
    } catch (_) {}
  }

  Future<void> _loadResolvedOpponentProfileIfNeeded(String opponentId) async {
    final id = opponentId.trim();
    if (id.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (row == null || !mounted) return;
      final display = (row['display_name'] ?? '').toString().trim();
      final username = (row['username'] ?? '').toString().trim();
      final avatar = _normalizeAvatar((row['avatar_url'] ?? '').toString());
      setState(() {
        _resolvedOpponentName = display.isNotEmpty
            ? display
            : (username.isNotEmpty ? '@$username' : 'Opponent');
        _competitor2AvatarUrl = avatar ?? _competitor2AvatarUrl;
      });
    } catch (_) {}
  }

  Future<void> _inviteOpponentToExistingBattle() async {
    final battleId = (_effectiveBattleId() ?? '').trim();
    if (battleId.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (_) => BattleInviteDialog(
        currentUserId: widget.currentUserId,
        currentUserRole: widget.competitor1Type,
        battleType: '1v1',
        onInviteSelected: (userId, userName, avatarUrl) {
          unawaited(
            _sendInviteToExistingBattle(
              battleId: battleId,
              toUid: userId,
              toName: userName,
              toAvatarUrl: avatarUrl,
            ),
          );
        },
      ),
    );
  }

  Future<bool> _sendInviteToExistingBattle({
    required String battleId,
    required String toUid,
    required String toName,
    required String? toAvatarUrl,
  }) async {
    try {
      await const BattleHostApi().sendInviteToExistingBattle(
        battleId: battleId,
        toUid: toUid,
      );
      if (!mounted) return false;
      setState(() {
        _forceCompetitor2Cleared = false;
        _overrideCompetitor2Id = toUid.trim();
        _overrideCompetitor2Name = toName.trim().isEmpty ? null : toName.trim();
        _resolvedOpponentId = toUid.trim();
        _resolvedOpponentName = toName.trim().isEmpty ? null : toName.trim();
        _competitor2AvatarUrl = _normalizeAvatar(toAvatarUrl) ?? _competitor2AvatarUrl;
      });
      await _realtimeService.setCompetitor2Id(toUid.trim());
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite sent.'),
          backgroundColor: WeAfricaColors.success,
        ),
      );
      return true;
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._sendInvite', e, st);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(e, fallback: 'Could not invite right now.'),
          ),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return false;
    }
  }

  Future<void> _sendGift(GiftModel gift, String toHostId) async {
    final target = toHostId.trim().isNotEmpty ? toHostId.trim() : widget.competitor1Id.trim();
    if (target.isEmpty) return;
    final res = await GiftService().sendGift(
      channelId: widget.channelId,
      toHostId: target,
      giftId: gift.id,
      senderName: widget.currentUserName,
      liveId: widget.liveId,
    );
    if (!mounted) return;
    res.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gift sent!'),
            backgroundColor: WeAfricaColors.success,
          ),
        );
      },
      loading: () {},
      error: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send gift.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
      },
    );
  }

  void _showGiftSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GiftSelectionSheet(
        competitor1Id: widget.competitor1Id,
        competitor1Name: widget.competitor1Name,
        competitor2Id: _effectiveCompetitor2Id,
        competitor2Name: _effectiveCompetitor2Name,
        onGiftSelected: (gift, toHostId) => unawaited(_sendGift(gift, toHostId)),
      ),
    );
  }

  Future<void> _persistBattlePatch(Map<String, Object?> patch) async {
    final battleId = (_effectiveBattleId() ?? '').trim();
    if (battleId.isEmpty) {
      throw StateError('Battle id missing');
    }

    await Supabase.instance.client
        .from('live_battles')
        .update(<String, Object?>{
          ...patch,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('battle_id', battleId);
  }

  Future<void> _openHostBeatPicker() async {
    if (_hostControlBusy) return;

    BeatModel? selectedBeat;
    final picked = await showModalBottomSheet<BeatModel?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: _GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Battle Beat',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    BeatSelectionWidget(
                      initialBeatId: _selectedBeatId,
                      onBeatSelected: (beat) {
                        selectedBeat = beat;
                      },
                    ),
                    const SizedBox(height: 12),
                    GoldButton(
                      label: 'APPLY BEAT',
                      onPressed: () => Navigator.of(sheetContext).pop(selectedBeat),
                      fullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _hostControlBusy = true;
      _selectedBeatId = picked.id;
      _selectedBeatName = picked.name;
      final alreadyInQueue = _djQueue.any((beat) => beat.id == picked.id);
      if (!alreadyInQueue) {
        _djQueue.insert(0, picked);
      }
      _djQueueIndex = _djQueue.indexWhere((beat) => beat.id == picked.id);
    });
    try {
      await _persistBattlePatch(<String, Object?>{'beat_name': picked.name});
      if (_djDeckPlaying && _shouldPublishBeat) {
        await _startSelectedBeatMixing();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Beat switched to ${picked.name}.'),
          backgroundColor: WeAfricaColors.success,
        ),
      );
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._openHostBeatPicker', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, fallback: 'Could not change beat right now.')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _hostControlBusy = false);
      }
    }
  }

  Future<void> _toggleHostBoostMode() async {
    if (_hostControlBusy) return;

    final nextValue = !_hostBoostEnabled;
    setState(() {
      _hostControlBusy = true;
      _hostBoostEnabled = nextValue;
    });

    try {
      await _persistBattlePatch(<String, Object?>{'crowd_boost_enabled': nextValue});
      final battleId = (_effectiveBattleId() ?? '').trim();
      if (battleId.isNotEmpty) {
        await BattleInteractionsService().sendChatMessage(
          battleId: battleId,
          userId: widget.currentUserId,
          userName: 'Battle Host',
          message: nextValue ? 'Crowd boost is ON. Push the room harder.' : 'Crowd boost is OFF. Back to standard battle mode.',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextValue ? 'Crowd boost activated.' : 'Crowd boost disabled.'),
          backgroundColor: nextValue ? WeAfricaColors.success : Colors.white12,
        ),
      );
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._toggleHostBoostMode', e, st);
      if (!mounted) return;
      setState(() => _hostBoostEnabled = !nextValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, fallback: 'Could not update crowd boost right now.')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _hostControlBusy = false);
      }
    }
  }

  Future<void> _dropChallenger() async {
    if (_hostControlBusy) return;
    if (_effectiveCompetitor2Id.isEmpty) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Drop Challenger'),
        content: Text('Remove $_effectiveCompetitor2Name from this battle and return to waiting mode, or rotate in the next queued challenger?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('drop'),
            child: const Text('Drop Only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('next'),
            child: const Text('Drop + Invite Next'),
          ),
        ],
      ),
    );

    if (action == null || action == 'cancel') return;
    final inviteNext = action == 'next';

    setState(() => _hostControlBusy = true);
    try {
      await _persistBattlePatch(<String, Object?>{
        'host_b_id': null,
        'host_b_ready': false,
        'host_b_agora_uid': null,
        'status': 'waiting',
      });
      await _realtimeService.setCompetitor2Id('');
      _battleController.resetForWaitingOpponent(competitor1Score: _battleController.competitor1Score);

      if (!mounted) return;
      setState(() {
        _forceCompetitor2Cleared = true;
        _overrideCompetitor2Id = null;
        _overrideCompetitor2Name = null;
        _resolvedOpponentId = null;
        _resolvedOpponentName = null;
        _competitor2AvatarUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(inviteNext ? 'Challenger dropped. Looking for the next queued artist.' : 'Challenger dropped. Battle returned to waiting mode.'),
          backgroundColor: WeAfricaColors.success,
        ),
      );

      if (inviteNext) {
        final accepted = await BattleInteractionsService().acceptNextRequest(
          battleId: (_effectiveBattleId() ?? '').trim(),
        );
        switch (accepted) {
          case AppSuccess<AcceptedBattleRequest>(:final data):
            final inviteSent = await _inviteRequesterFromQueue(data.requesterId);
            if (!mounted) return;
            if (!inviteSent) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Next challenger was selected but the invite could not be sent.'),
                  backgroundColor: WeAfricaColors.error,
                ),
              );
              await _openQueuePanel();
            }
          default:
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No pending challenger in the queue yet.'),
                backgroundColor: WeAfricaColors.error,
              ),
            );
            await _openQueuePanel();
        }
      }

      await _refreshBattleStatus();
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._dropChallenger', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, fallback: 'Could not drop challenger right now.')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _hostControlBusy = false);
      }
    }
  }

  Future<void> _openBattlePanel({
    _BattlePanelTab initialTab = _BattlePanelTab.chat,
  }) async {
    final battleId = (_effectiveBattleId() ?? '').trim();
    if (battleId.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlassBattleRoomSheet(
        battleId: battleId,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        competitor1Id: widget.competitor1Id,
        competitor1Name: widget.competitor1Name,
        competitor2Id: _effectiveCompetitor2Id,
        competitor2Name: _effectiveCompetitor2Name,
        isHost: _resolveUserRole() == UserRole.host,
        initialTab: initialTab,
        onInviteRequester: _inviteRequesterFromQueue,
      ),
    );
  }

  Future<bool> _inviteRequesterFromQueue(String requesterId) async {
    final battleId = (_effectiveBattleId() ?? '').trim();
    if (battleId.isEmpty || requesterId.trim().isEmpty) return false;

    String requesterName = requesterId;
    String? avatarUrl;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', requesterId.trim())
          .maybeSingle();
      if (row != null) {
        final display = (row['display_name'] ?? '').toString().trim();
        final username = (row['username'] ?? '').toString().trim();
        requesterName = display.isNotEmpty
            ? display
            : (username.isNotEmpty ? '@$username' : requesterId.trim());
        avatarUrl = _normalizeAvatar((row['avatar_url'] ?? '').toString());
      }
    } catch (_) {}

    return _sendInviteToExistingBattle(
      battleId: battleId,
      toUid: requesterId.trim(),
      toName: requesterName,
      toAvatarUrl: avatarUrl,
    );
  }

  Future<void> _openQueuePanel() {
    return _openBattlePanel(initialTab: _BattlePanelTab.queue);
  }

  void _showEndLiveDialog() {
    if (_endingLive) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Live Stream'),
        content: const Text('Are you sure you want to end this battle stream?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_endLiveStream());
            },
            child: const Text('End'),
          ),
        ],
      ),
    );
  }

  Future<void> _endLiveStream() async {
    if (_endingLive) return;
    setState(() {
      _endingLive = true;
      _isLoading = true;
    });
    try {
      await _streamController.leaveChannel();
      await LiveSessionService().endLiveAndEnsureCleared(
        hostId: widget.competitor1Id,
        channelId: widget.channelId,
      );
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e, st) {
      UserFacingError.log('ProfessionalBattleScreen._endLiveStream', e, st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _endingLive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              e,
              fallback: 'Could not end live stream. Please try again.',
            ),
          ),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  void _handleBattleEnded() {
    if (!mounted || _winnerShown) return;
    _winnerShown = true;
    if (_battleController.isDraw) {
      _showWinnerAnnouncement("It's a tie!");
      return;
    }
    final winnerUid = (_battleController.winnerUid ?? '').trim();
    if (winnerUid == widget.competitor1Id.trim()) {
      _showWinnerAnnouncement('${widget.competitor1Name} wins!');
      return;
    }
    if (winnerUid == _effectiveCompetitor2Id) {
      _showWinnerAnnouncement('$_effectiveCompetitor2Name wins!');
      return;
    }
    final s1 = _battleController.competitor1Score;
    final s2 = _battleController.competitor2Score;
    if (s1 == s2) {
      _showWinnerAnnouncement("It's a tie!");
    } else {
      _showWinnerAnnouncement(s1 > s2
          ? '${widget.competitor1Name} wins!'
          : '$_effectiveCompetitor2Name wins!');
    }
  }

  void _showWinnerAnnouncement(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Battle Ended'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _shareBattle() {
    final text = 'Join the live battle on WeAfrica Music!\nChannel: ${widget.channelId}';
    Share.share(text, subject: 'WeAfrica Music Battle');
  }

  void _throttledReaction() {
    if (_reactionThrottle?.isActive ?? false) return;
    _reactionThrottle = Timer(const Duration(milliseconds: 450), () {});
    late final FloatingHeart heart;
    heart = FloatingHeart(
      key: UniqueKey(),
      onComplete: (completed) {
        if (!mounted) return;
        setState(() => _floatingHearts.remove(completed));
      },
    );
    setState(() => _floatingHearts.add(heart));
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _formatBattleClock(int totalSeconds) {
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool get _canUsePerformerMode {
    final role = _resolveUserRole();
    return role == UserRole.host || role == UserRole.opponent;
  }

  String _performerModePrefKey() {
    final battleId = (_effectiveBattleId() ?? '').trim();
    final channelId = widget.channelId.trim();
    final keySeed = battleId.isNotEmpty ? battleId : channelId;
    return 'performer_mode:$keySeed';
  }

  Future<void> _loadPerformerModePreference() async {
    if (_performerModeLoaded) return;

    if (!_canUsePerformerMode) {
      _performerModeLoaded = true;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_performerModePrefKey()) ?? false;
      if (!mounted) return;
      setState(() {
        _performerMode = value;
        _performerModeLoaded = true;
      });
    } catch (_) {
      _performerModeLoaded = true;
    }
  }

  Future<void> _togglePerformerMode() async {
    if (!_canUsePerformerMode) return;

    final next = !_performerMode;
    setState(() => _performerMode = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_performerModePrefKey(), next);
    } catch (_) {
      // Best-effort.
    }
  }

  Widget _buildBattleTopBar({
    required int competitor1Score,
    required int competitor2Score,
    required int timeLeft,
    required int commentsCount,
  }) {
    final total = competitor1Score + competitor2Score;
    final leftFlex = total == 0 ? 1 : (competitor2Score <= 0 ? 1 : competitor2Score);
    final rightFlex = total == 0 ? 1 : (competitor1Score <= 0 ? 1 : competitor1Score);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _effectiveCompetitor2Name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _formatBattleClock(timeLeft),
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        widget.competitor1Name,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _resolveUserRole() == UserRole.host ? _showEndLiveDialog : () => Navigator.of(context).maybePop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: Text(
                          _resolveUserRole() == UserRole.host ? 'END' : 'LEAVE',
                          style: TextStyle(
                            color: _resolveUserRole() == UserRole.host ? Colors.redAccent : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    if (_canUsePerformerMode) ...[
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _togglePerformerMode,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Icon(
                              _performerMode ? Icons.visibility : Icons.visibility_off,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  flex: leftFlex,
                  child: Container(color: Colors.blue),
                ),
                Expanded(
                  flex: rightFlex,
                  child: Container(color: Colors.red),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$competitor2Score pts',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Text(
                  'Coins: $_totalSpentCoins / ${_coinGoal ?? 0}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Text(
                  '$competitor1Score pts',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _isOffline ? 'Offline' : 'Live',
                style: TextStyle(
                  color: _isOffline ? Colors.white54 : Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_performerMode) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.55)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off, size: 12, color: WeAfricaColors.gold),
                      SizedBox(width: 4),
                      Text(
                        'PERFORMER MODE',
                        style: TextStyle(color: WeAfricaColors.gold, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Text(
                'Viewers: ${_formatCount(_viewerCount)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              Text(
                'Comments: $commentsCount',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBattleStage(BuildContext context, BattleController battle) {
    final status = _lastBattleStatus;
    final timeline = status == null ? null : _computeTimelineSnapshot(status);

    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hostBoostEnabled
                ? WeAfricaColors.gold.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.08),
            width: _hostBoostEnabled ? 2 : 1,
          ),
          boxShadow: _hostBoostEnabled
              ? [
                  BoxShadow(
                    color: WeAfricaColors.gold.withValues(alpha: 0.18),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: BattleSplitView(
                // Keep host on the right side of the stage.
                competitor1Name: _effectiveCompetitor2Name,
                competitor2Name: widget.competitor1Name,
                competitor1Type: widget.competitor2Type,
                competitor2Type: widget.competitor1Type,
                isCompetitor1Leading: battle.competitor2Score > battle.competitor1Score,
                isCompetitor2Leading: battle.competitor1Score > battle.competitor2Score,
                rtcEngine: _streamController.engine,
                channelId: widget.channelId,
                remoteUids: _streamController.remoteVideoUids,
                competitor1AgoraUid: _effectiveCompetitor2Id.isEmpty
                    ? null
                    : _stableAgoraUid(_effectiveCompetitor2Id),
                competitor2AgoraUid: _stableAgoraUid(widget.competitor1Id),
                localIsCompetitor1: widget.currentUserId.trim() == _effectiveCompetitor2Id,
                localIsCompetitor2: widget.currentUserId.trim() == widget.competitor1Id.trim(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.42),
                    ],
                    stops: const [0, 0.55, 0.8, 1],
                  ),
                ),
              ),
            ),
            const Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.black,
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (timeline != null)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: _TimelinePhaseBar(
                  phase: timeline.phase,
                  remainingSeconds: timeline.remainingSecondsInPhase,
                  isPaused: timeline.isPaused,
                  performerAName: widget.competitor1Name,
                  performerBName: _effectiveCompetitor2Name,
                ),
              ),
            if (timeline != null)
              Positioned(
                left: 10,
                bottom: 54,
                child: _TurnPill(
                  label: timeline.phase == _BattleTimelinePhase.performerB ? 'YOUR TURN' : 'MUTED',
                  active: timeline.phase == _BattleTimelinePhase.performerB,
                ),
              ),
            if (timeline != null)
              Positioned(
                right: 10,
                bottom: 54,
                child: _TurnPill(
                  label: timeline.phase == _BattleTimelinePhase.performerA ? 'YOUR TURN' : 'MUTED',
                  active: timeline.phase == _BattleTimelinePhase.performerA,
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Row(
                children: [
                  Expanded(
                    child: _BattleContestantLabel(
                      alignment: Alignment.bottomLeft,
                      name: _effectiveCompetitor2Name,
                      avatarUrl: _competitor2AvatarUrl,
                      color: Colors.blue.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _BattleContestantLabel(
                      alignment: Alignment.bottomRight,
                      name: widget.competitor1Name,
                      avatarUrl: _competitor1AvatarUrl,
                      color: Colors.red.withValues(alpha: 0.75),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostControlTray() {
    // Hide for performers and when performer mode is on
    if (_performerMode) return const SizedBox.shrink();
    if (_resolveUserRole() != UserRole.host) return const SizedBox.shrink();

    unawaited(_ensureTimelineInitializedIfNeeded());

    final status = _lastBattleStatus;
    final timeline = status == null ? null : _computeTimelineSnapshot(status);

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 116,
      right: 12,
      child: _HostControlTray(
        busy: _hostControlBusy,
        micMuted: _manualMicMuted,
        timelinePaused: timeline?.isPaused ?? false,
        showTimelineControls: timeline != null,
        onPauseTap: _toggleTimelinePause,
        onNextTurnTap: _skipToNextPhase,
        onMuteMicTap: _toggleManualMicMute,
      ),
    );
  }

  Widget _buildHostMetricsPanel() {
    final flowers = (_totalSpentCoins * 0.48).round();
    final diamonds = (_totalSpentCoins * 0.22).round();
    final drumPower = (_totalSpentCoins * 0.30).round();
    final earnings = (_totalSpentCoins * 0.02);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _HostStatusPill(
                icon: Icons.radio_button_checked,
                label: 'LIVE',
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              _HostStatusPill(
                icon: Icons.visibility,
                label: '${_formatCount(_viewerCount)} watching',
                color: Colors.lightBlueAccent,
              ),
              const Spacer(),
              Text(
                'Earnings: \$${earnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: WeAfricaColors.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HostGoalProgress(
            label: 'Flowers',
            current: flowers,
            target: 2000,
            color: Colors.pinkAccent,
          ),
          const SizedBox(height: 6),
          _HostGoalProgress(
            label: 'Diamonds',
            current: diamonds,
            target: 333,
            color: Colors.cyanAccent,
          ),
          const SizedBox(height: 6),
          _HostGoalProgress(
            label: 'Drum Power',
            current: drumPower,
            target: 250,
            color: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildHostActionDock() {
    final role = _resolveUserRole();
    if (role != UserRole.host && role != UserRole.opponent) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHostMetricsPanel(),
          if (_isDjPerformer) ...[
            const SizedBox(height: 10),
            _buildDjConsolePanel(),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BattleActionButton(
                    icon: Icons.person_add_alt_1,
                    color: WeAfricaColors.gold,
                    onTap: _inviteOpponentToExistingBattle,
                  ),
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: Icons.cameraswitch,
                    color: Colors.white,
                    onTap: _switchCameraLens,
                  ),
					if (!_isDjPerformer && _shouldPublishBeat) ...[
						const SizedBox(width: 8),
						_BattleActionButton(
							icon: _djDeckPlaying ? Icons.pause_circle : Icons.play_circle,
							color: _djDeckPlaying ? Colors.orangeAccent : Colors.lightGreenAccent,
							onTap: _toggleDjPlaybackTap,
						),
						const SizedBox(width: 8),
						_BattleActionButton(
							icon: Icons.queue_music,
							color: Colors.lightBlueAccent,
							onTap: _openHostBeatPicker,
						),
					],
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: _manualMicMuted ? Icons.mic_off : Icons.mic,
                    color: _manualMicMuted ? Colors.redAccent : Colors.lightGreenAccent,
                    onTap: _toggleManualMicMute,
                  ),
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: _localVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    color: _localVideoEnabled ? Colors.white : Colors.redAccent,
                    onTap: _toggleLocalVideo,
                  ),
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: _hostCommentsVisible ? Icons.comment : Icons.comments_disabled,
                    color: _hostCommentsVisible ? Colors.white70 : Colors.white38,
                    onTap: () => setState(() => _hostCommentsVisible = !_hostCommentsVisible),
                  ),
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: _hostBoostEnabled ? Icons.electric_bolt : Icons.flash_on,
                    color: _hostBoostEnabled ? WeAfricaColors.gold : Colors.white70,
                    onTap: _toggleHostBoostMode,
                  ),
                  const SizedBox(width: 8),
                  _BattleActionButton(
                    icon: Icons.person_remove_alt_1,
                    color: Colors.orangeAccent,
                    onTap: _dropChallenger,
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: _showEndLiveDialog,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End Live'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDjConsolePanel() {
    final currentTrack = (_djQueue.isNotEmpty && _djQueueIndex >= 0 && _djQueueIndex < _djQueue.length)
        ? _djQueue[_djQueueIndex]
        : null;
    final currentTrackName = _selectedBeatName.isNotEmpty
        ? _selectedBeatName
        : (currentTrack?.name ?? 'No track selected');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: WeAfricaColors.gold),
              const SizedBox(width: 8),
              const Text(
                'DJ Console',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                currentTrackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _BattleActionButton(
                icon: _djDeckPlaying ? Icons.pause_circle : Icons.play_circle,
                color: _djDeckPlaying ? Colors.orangeAccent : Colors.lightGreenAccent,
                onTap: _toggleDjPlaybackTap,
              ),
              const SizedBox(width: 8),
              _BattleActionButton(
                icon: Icons.skip_next,
                color: Colors.white,
                onTap: _skipDjTrack,
              ),
              const SizedBox(width: 8),
              _BattleActionButton(
                icon: Icons.queue_music,
                color: Colors.lightBlueAccent,
                onTap: _openHostBeatPicker,
              ),
              const SizedBox(width: 8),
              _BattleActionButton(
                icon: Icons.blur_on,
                color: _djReverbEnabled ? WeAfricaColors.gold : Colors.white54,
                onTap: () => setState(() => _djReverbEnabled = !_djReverbEnabled),
              ),
              const SizedBox(width: 8),
              _BattleActionButton(
                icon: Icons.multitrack_audio,
                color: _djEchoEnabled ? WeAfricaColors.gold : Colors.white54,
                onTap: () => setState(() => _djEchoEnabled = !_djEchoEnabled),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 96,
                child: Text('Master Vol', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _djMasterVolume,
                  min: 0,
                  max: 1,
                  activeColor: WeAfricaColors.gold,
                  onChanged: (value) => setState(() => _djMasterVolume = value),
                ),
              ),
              Text('${(_djMasterVolume * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 96,
                child: Text('Mic Vol', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _djMicVolume,
                  min: 0,
                  max: 1,
                  activeColor: Colors.lightGreenAccent,
                  onChanged: (value) => setState(() => _djMicVolume = value),
                ),
              ),
              Text('${(_djMicVolume * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel({
    required BuildContext context,
    required int commentsCount,
  }) {
    // Hide if performer mode is on
    if (_performerMode) return const SizedBox.shrink();
    
    // Host/opponent get a dedicated control dock.
    final role = _resolveUserRole();
    if (role == UserRole.host || role == UserRole.opponent) {
      return _buildHostActionDock();
    }
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _openBattlePanel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              width: double.infinity,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Write a comment...',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  if (commentsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$commentsCount',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _BattleActionButton(icon: Icons.chat_bubble, color: Colors.white, onTap: _openBattlePanel),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.local_fire_department, color: Colors.red, onTap: _throttledReaction),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.card_giftcard, color: Colors.orange, onTap: _showGiftSheet),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.flash_on, color: Colors.yellow, onTap: _shareBattle),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.emoji_events, color: Colors.amber, onTap: _openBattlePanel),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.mic, color: Colors.purpleAccent, onTap: _openBattlePanel),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.headphones, color: Colors.blueAccent, onTap: _openBattlePanel),
                const SizedBox(width: 10),
                _BattleActionButton(icon: Icons.album, color: Colors.greenAccent, onTap: _shareBattle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _battleStatusTimer?.cancel();
    _reactionThrottle?.cancel();
    _timelineTick?.cancel();
    unawaited(_viewerCountSub?.cancel() ?? Future<void>.value());
    unawaited(_scoreSub?.cancel() ?? Future<void>.value());
    unawaited(_giftSub?.cancel() ?? Future<void>.value());
    unawaited(_connectivitySub?.cancel() ?? Future<void>.value());
    _streamController.dispose();
    _battleController.dispose();
    _giftController.dispose();
    unawaited(_realtimeService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: WeAfricaColors.gold, size: 44),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              GoldButton(
                label: 'GO BACK',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _streamController),
        ChangeNotifierProvider.value(value: _battleController),
        ChangeNotifierProvider.value(value: _giftController),
      ],
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) {
            final battle = context.watch<BattleController>();
            final s1 = battle.competitor1Score;
            final s2 = battle.competitor2Score;
            final battleId = (_effectiveBattleId() ?? '').trim();
            final liveId = (widget.liveId ?? '').trim();
            final commentsStream = battleId.isNotEmpty
                ? BattleInteractionsService().watchChat(battleId: battleId, limit: 30)
                : (liveId.isEmpty ? null : ChatService().watchMessages(liveId: liveId, limit: 30));

            return StreamBuilder<Object>(
              stream: commentsStream,
              builder: (context, snapshot) {
                final data = snapshot.data;
                final commentsCount = switch (data) {
                  List<BattleChatEntry> value => value.length,
                  List<ChatMessageModel> value => value.length,
                  _ => 0,
                };

                final status = _lastBattleStatus;
                final timelineSnapshot = status == null ? null : _computeTimelineSnapshot(status);
                final transitionSeconds = (status != null && timelineSnapshot != null)
                    ? _transitionCountdownSeconds(status, timelineSnapshot)
                    : 0;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeArea(
                      child: Column(
                        children: [
                          _buildBattleTopBar(
                            competitor1Score: s1,
                            competitor2Score: s2,
                            timeLeft: battle.timeRemaining,
                            commentsCount: commentsCount,
                          ),
                          Expanded(child: _buildBattleStage(context, battle)),
                          _buildBottomPanel(
                            context: context,
                            commentsCount: commentsCount,
                          ),
                        ],
                      ),
                    ),
                    _buildHostControlTray(),
                    // Floating comments - only for viewers (not artists/DJs)
                    if (!_performerMode && _resolveUserRole() == UserRole.audience)
                      Positioned(
                        left: 12,
                        right: MediaQuery.sizeOf(context).width * 0.30,
                        bottom: 126,
                        child: _GlassFloatingCommentsOverlay(
                          battleId: battleId,
                          liveId: liveId,
                        ),
                      ),
                    if (!_performerMode && (_resolveUserRole() == UserRole.host || _resolveUserRole() == UserRole.opponent) && _hostCommentsVisible)
                      Positioned(
                        left: 12,
                        right: MediaQuery.sizeOf(context).width * 0.34,
                        bottom: 190,
                        child: _GlassFloatingCommentsOverlay(
                          battleId: battleId,
                          liveId: liveId,
                        ),
                      ),
                    FloatingHeartsLayer(hearts: _floatingHearts),
                    // Gift animations - only for viewers (not artists/DJs)
                    if (!_performerMode && _resolveUserRole() == UserRole.audience)
                      const GiftAnimationOverlay(),
                    if (transitionSeconds > 0)
                      _TimelineTransitionOverlay(timeRemaining: transitionSeconds),
                    ValueListenableBuilder<Set<int>>(
                      valueListenable: _streamController.remoteVideoUidsNotifier,
                      builder: (context, remoteVideoUids, _) {
                        if (!_isWaitingForOpponent) return const SizedBox.shrink();
                        final message = (_resolvedOpponentName ?? '').trim().isNotEmpty
                            ? 'Invite sent to ${_resolvedOpponentName!.trim()}. Waiting for them to join.'
                            : 'Invite an artist or DJ to join this battle.';
                        return Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.64)),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 360),
                                child: _GlassCard(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Waiting for opponent',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          message,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: GoldButton(
                                                label: 'INVITE',
                                                onPressed: _inviteOpponentToExistingBattle,
                                                fullWidth: true,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: _endLiveStream,
                                                child: const Text('CANCEL'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BattleContestantLabel extends StatelessWidget {
  const _BattleContestantLabel({
    required this.alignment,
    required this.name,
    required this.avatarUrl,
    required this.color,
    this.textAlign = TextAlign.start,
  });

  final Alignment alignment;
  final String name;
  final String? avatarUrl;
  final Color color;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim().isEmpty ? 'Unknown' : name.trim();
    final initial = trimmedName.substring(0, 1).toUpperCase();

    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black.withValues(alpha: 0.30),
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                trimmedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleActionButton extends StatelessWidget {
  const _BattleActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}

class _HostGoalProgress extends StatelessWidget {
  const _HostGoalProgress({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  final String label;
  final int current;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeTarget = target <= 0 ? 1 : target;
    final ratio = (current / safeTarget).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '$current/$target',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: ratio,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _HostStatusPill extends StatelessWidget {
  const _HostStatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BattleTimelinePhase {
  notStarted,
  performerA,
  performerB,
  judging,
  complete,
}

@immutable
class _BattleTimelineSnapshot {
  const _BattleTimelineSnapshot({
    required this.phase,
    required this.remainingSecondsInPhase,
    required this.elapsedSeconds,
    required this.isPaused,
    required this.perfASeconds,
    required this.perfBSeconds,
    required this.judgingSeconds,
  });

  final _BattleTimelinePhase phase;
  final int remainingSecondsInPhase;
  final int elapsedSeconds;
  final bool isPaused;
  final int perfASeconds;
  final int perfBSeconds;
  final int judgingSeconds;
}

class _TimelinePhaseBar extends StatelessWidget {
  const _TimelinePhaseBar({
    required this.phase,
    required this.remainingSeconds,
    required this.isPaused,
    required this.performerAName,
    required this.performerBName,
  });

  final _BattleTimelinePhase phase;
  final int remainingSeconds;
  final bool isPaused;
  final String performerAName;
  final String performerBName;

  String _format(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  String _label() {
    switch (phase) {
      case _BattleTimelinePhase.performerA:
        return '${performerAName.trim().isEmpty ? 'Artist 1' : performerAName.trim()} TURN';
      case _BattleTimelinePhase.performerB:
        return '${performerBName.trim().isEmpty ? 'Artist 2' : performerBName.trim()} TURN';
      case _BattleTimelinePhase.judging:
        return 'JUDGING / WRAP-UP';
      case _BattleTimelinePhase.complete:
        return 'BATTLE COMPLETE';
      case _BattleTimelinePhase.notStarted:
        return 'STARTING...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPaused ? Icons.pause_circle_filled : Icons.timer,
                size: 16,
                color: isPaused ? Colors.white70 : Colors.amber,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _format(remainingSeconds),
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnPill extends StatelessWidget {
  const _TurnPill({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: (active ? Colors.greenAccent : Colors.white54).withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.greenAccent : Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineTransitionOverlay extends StatefulWidget {
  const _TimelineTransitionOverlay({required this.timeRemaining});

  final int timeRemaining;

  @override
  State<_TimelineTransitionOverlay> createState() => _TimelineTransitionOverlayState();
}

class _TimelineTransitionOverlayState extends State<_TimelineTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.85), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1 + _controller.value * 0.10,
                      child: child,
                    );
                  },
                  child: const Icon(Icons.swap_horiz, color: WeAfricaColors.gold, size: 44),
                ),
                const SizedBox(height: 14),
                const Text(
                  'SWITCHING TURNS',
                  style: TextStyle(
                    color: WeAfricaColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Next performer in ${widget.timeRemaining}s',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _HostControlTray extends StatelessWidget {
  const _HostControlTray({
    required this.busy,
    required this.micMuted,
    required this.timelinePaused,
    required this.showTimelineControls,
    required this.onPauseTap,
    required this.onNextTurnTap,
    required this.onMuteMicTap,
  });

  final bool busy;
  final bool micMuted;
  final bool timelinePaused;
  final bool showTimelineControls;
  final VoidCallback onPauseTap;
  final VoidCallback onNextTurnTap;
  final VoidCallback onMuteMicTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTimelineControls)
                Row(
                  children: [
                    Expanded(
                      child: _HostTrayButton(
                        icon: timelinePaused ? Icons.play_arrow : Icons.pause,
                        label: timelinePaused ? 'Resume' : 'Pause',
                        onTap: busy ? null : onPauseTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HostTrayButton(
                        icon: Icons.skip_next,
                        label: 'Next',
                        onTap: busy ? null : onNextTurnTap,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              _HostTrayButton(
                icon: micMuted ? Icons.mic_off : Icons.mic,
                label: micMuted ? 'Unmute Mic' : 'Mute Mic',
                onTap: busy ? null : onMuteMicTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostTrayButton extends StatelessWidget {
  const _HostTrayButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.white.withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: enabled ? Colors.white : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BattlePanelTab { chat, queue }

class _GlassBattleRoomSheet extends StatelessWidget {
  const _GlassBattleRoomSheet({
    required this.battleId,
    required this.currentUserId,
    required this.currentUserName,
    required this.competitor1Id,
    required this.competitor1Name,
    required this.competitor2Id,
    required this.competitor2Name,
    required this.isHost,
    required this.initialTab,
    required this.onInviteRequester,
  });

  final String battleId;
  final String currentUserId;
  final String currentUserName;
  final String competitor1Id;
  final String competitor1Name;
  final String competitor2Id;
  final String competitor2Name;
  final bool isHost;
  final _BattlePanelTab initialTab;
  final Future<bool> Function(String requesterId) onInviteRequester;

  @override
  Widget build(BuildContext context) {
    final isQueue = initialTab == _BattlePanelTab.queue;
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isQueue ? 'Battle Queue' : 'Battle Chat',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isQueue)
                Expanded(
                  child: Center(
                    child: Text(
                      isHost
                          ? 'Queue actions are available for host controls.'
                          : 'Queue is managed by the host.',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
                  child: StreamBuilder<List<BattleChatEntry>>(
                    stream: BattleInteractionsService().watchChat(battleId: battleId, limit: 30),
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? const <BattleChatEntry>[];
                      if (items.isEmpty) {
                        return const Center(
                          child: Text('No messages yet.', style: TextStyle(color: Colors.white54)),
                        );
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = items[index];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${entry.userName}: ${entry.message}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassFloatingCommentsOverlay extends StatelessWidget {
  const _GlassFloatingCommentsOverlay({
    required this.battleId,
    required this.liveId,
  });

  final String battleId;
  final String liveId;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const Text(
            'Live comments',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class FloatingHeart extends StatefulWidget {
  const FloatingHeart({
    super.key,
    required this.onComplete,
  });

  final ValueChanged<FloatingHeart> onComplete;

  @override
  State<FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete(widget);
      }
    });
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final t = _progress.value;
        return Positioned(
          right: 40 + (t * 24),
          bottom: 110 + (t * 180),
          child: Opacity(
            opacity: 1 - t,
            child: Transform.scale(
              scale: 0.8 + (t * 0.6),
              child: const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class FloatingHeartsLayer extends StatelessWidget {
  const FloatingHeartsLayer({
    super.key,
    required this.hearts,
  });

  final List<FloatingHeart> hearts;

  @override
  Widget build(BuildContext context) {
    if (hearts.isEmpty) return const SizedBox.shrink();
    return Stack(children: hearts);
  }
}