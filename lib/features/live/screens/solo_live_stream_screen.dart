import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/widgets/glass_card.dart';
import '../controllers/gift_controller.dart';
import '../controllers/live_stream_controller.dart';
import '../models/beat_model.dart';
import '../models/chat_message_model.dart';
import '../models/gift_model.dart';
import '../models/live_session_model.dart';
import '../services/beat_service.dart';
import '../services/chat_service.dart';
import '../services/live_realtime_service.dart';
import '../services/live_session_service.dart';
import '../widgets/beat_selection_widget.dart';
import '../widgets/gift/gift_animation_overlay.dart';
import '../widgets/gift/gift_selection_sheet.dart';
import '../../beats/services/beat_download_service.dart';

class SoloLiveStreamScreen extends StatefulWidget {
  const SoloLiveStreamScreen({
    super.key,
    required this.title,
    required this.hostName,
    required this.channelId,
    this.token,
    this.liveStreamId,
    this.beatId,
    this.flowerGoalTarget,
    this.diamondGoalTarget,
    this.drumGoalTarget,
  });

  final String title;
  final String hostName;
  final String channelId;
  final String? token;
  final String? liveStreamId;
  final String? beatId;
  final int? flowerGoalTarget;
  final int? diamondGoalTarget;
  final int? drumGoalTarget;

  @override
  State<SoloLiveStreamScreen> createState() => _SoloLiveStreamScreenState();
}

class _SoloLiveStreamScreenState extends State<SoloLiveStreamScreen>
    with WidgetsBindingObserver {
  static const int _maxOnScreenMessages = 6;
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const Duration _energyTick = Duration(milliseconds: 260);
  static const Duration _bigGiftMinInterval = Duration(seconds: 2);

  late final LiveStreamController _streamController;
  late final GiftController _giftController;
  late final LiveRealtimeService _realtime;

  StreamSubscription<int>? _viewerSub;
  StreamSubscription<Map<String, int>>? _scoreSub;
  StreamSubscription<GiftModel>? _giftSub;
  StreamSubscription<List<ChatMessageModel>>? _chatSub;

  Timer? _heartbeatTimer;
  Timer? _energyTimer;
  Timer? _bigGiftTimer;

  bool _isLoading = true;
  bool _ending = false;
  String? _error;

  int _viewerCount = 0;
  int _diamonds = 0;

  final List<ChatMessageModel> _recentMessages = <ChatMessageModel>[];
  final List<FloatingHeart> _hearts = <FloatingHeart>[];

  final ValueNotifier<double> _energy = ValueNotifier<double>(0);

  bool _micMuted = false;
  bool _localVideoEnabled = true;

  BeatModel? _selectedBeat;
  bool _beatBusy = false;
  bool _beatStartAttempted = false;

  GiftModel? _bigGift;
  DateTime? _lastBigGiftShownAt;

  String get _hostId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) return uid.trim();
    return 'host';
  }

  int get _hostAgoraUid {
    // Must match the UID used when minting the host RTC token.
    // (See LiveSessionService.createSession -> _stableAgoraUid(hostId).)
    final h = _hostId.hashCode.abs();
    final uid = (h % 2000000000);
    return uid == 0 ? 1 : uid;
  }

  String get _liveId => widget.liveStreamId?.trim() ?? widget.channelId.trim();

  int get _diamondGoalTarget =>
      (widget.diamondGoalTarget ?? 10000).clamp(1, 1000000000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _streamController = LiveStreamController();
    _giftController = GiftController();
_realtime = LiveRealtimeService(
      channelId: widget.channelId,
      competitor1Id: _hostId,
      competitor2Id: '',
    );

    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      await _realtime.connect();

      _viewerSub = _realtime.viewerCountStream.listen((count) {
        if (!mounted) return;
        setState(() => _viewerCount = count);
      });

      _scoreSub = _realtime.scoreStream.listen((scores) {
        if (!mounted) return;
        final diamonds = (scores['competitor1'] ?? 0);
        setState(() => _diamonds = diamonds);
      });

      _giftSub = _realtime.giftStream.listen((gift) {
        _giftController.receiveGift(gift);
        _bumpEnergy(0.06);
        _maybeShowBigGift(gift);
      });

      _chatSub = ChatService().watchMessages(liveId: _liveId).listen((
        messages,
      ) {
        if (!mounted) return;
        setState(() {
          _recentMessages
            ..clear()
            ..addAll(
              messages.take(_maxOnScreenMessages).toList(growable: false),
            );
        });
        if (messages.isNotEmpty) {
          _bumpEnergy(0.01);
        }
      });

      final ok = await _streamController.initialize(
        channelId: widget.channelId,
        token: widget.token ?? '',
        role: UserRole.host,
        uid: _hostAgoraUid,
      );

      if (!ok) {
        throw StateError(
          'Could not start the stream. Please check permissions and try again.',
        );
      }

      await LiveSessionService().heartbeat(channelId: widget.channelId);
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        unawaited(LiveSessionService().heartbeat(channelId: widget.channelId));
      });

      _energyTimer = Timer.periodic(_energyTick, (_) {
        final v = _energy.value;
        if (v <= 0) return;
        _energy.value = (v - 0.008).clamp(0.0, 1.0);
      });

      unawaited(_maybeStartBackgroundBeat());

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, st) {
      UserFacingError.log('Solo live init failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _maybeStartBackgroundBeat() async {
    if (_beatStartAttempted) return;
    _beatStartAttempted = true;

    if (kIsWeb) return;
    final beatId = (widget.beatId ?? '').trim();
    if (beatId.isEmpty) return;

    try {
      final beat = await BeatService().getBeatById(beatId);
      if (!mounted || beat == null) return;
      _selectedBeat = beat;

      final audioUrl = await beat.resolveAudioUrl(Supabase.instance.client);
      if (!mounted) return;
      if (audioUrl == null || audioUrl.trim().isEmpty) return;

final filePath = await BeatDownloadService().downloadMp3(
        url: audioUrl,
        fileNameStem: 'solo_${beat.id}',
      );
      if (!mounted) return;

      await _streamController.startBackgroundBeat(
        filePath: filePath,
        publishVolumePercent: 55,
        playoutVolumePercent: 65,
        loop: true,
      );
    } catch (e, st) {
      UserFacingError.log('Auto beat start failed', e, st);
    }
  }

  void _bumpEnergy(double delta) {
    _energy.value = (_energy.value + delta).clamp(0.0, 1.0);
  }

  void _addHeart({bool countsTowardEnergy = true}) {
    if (_hearts.length >= 18) return;
    final heart = FloatingHeart(
      onComplete: (h) {
        if (!mounted) return;
        setState(() => _hearts.remove(h));
      },
    );
    setState(() => _hearts.add(heart));
    if (countsTowardEnergy) {
      _bumpEnergy(0.02);
    }
  }

  void _maybeShowBigGift(GiftModel gift) {
    final now = DateTime.now();
    final last = _lastBigGiftShownAt;
    if (last != null && now.difference(last) < _bigGiftMinInterval) return;

    _lastBigGiftShownAt = now;
    _bigGiftTimer?.cancel();

    setState(() {
      _bigGift = gift;
    });

    _bigGiftTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _bigGift = null);
    });
  }

  Future<void> _toggleMic() async {
    final engine = _streamController.engine;
    if (engine == null) return;

    final nextMuted = !_micMuted;
    try {
      await engine.muteLocalAudioStream(nextMuted);
      if (!mounted) return;
      setState(() => _micMuted = nextMuted);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _toggleCamera() async {
    final engine = _streamController.engine;
    if (engine == null) return;

    final nextEnabled = !_localVideoEnabled;
    try {
      await engine.muteLocalVideoStream(!nextEnabled);
      if (!mounted) return;
      setState(() => _localVideoEnabled = nextEnabled);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _switchCamera() async {
    final engine = _streamController.engine;
    if (engine == null) return;

    try {
      await engine.switchCamera();
    } catch (_) {
      // ignore
    }
  }

  void _openBeatSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: GlassCard(
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.music_note, color: WeAfricaColors.gold),
                      const SizedBox(width: 8),
                      const Text(
                        'Select Beat',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BeatSelectionWidget(
                    initialBeatId: _selectedBeat?.id,
                    onBeatSelected: (beat) {
                      _selectedBeat = beat;
                    },
                  ),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _streamController,
                    builder: (context, _) {
                      final playing = _streamController.backgroundBeatPlaying;
                      final hasBeat = _selectedBeat != null;
                      return Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_beatBusy || !hasBeat)
                                  ? null
                                  : () => _startSelectedBeatAndClose(),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WeAfricaColors.gold,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _beatBusy
                                  ? null
                                  : () async {
                                      if (playing) {
                                        await _streamController
                                            .pauseBackgroundBeat();
                                      } else {
                                        await _streamController
                                            .resumeBackgroundBeat();
                                      }
                                    },
                              icon: Icon(
                                playing
                                    ? Icons.pause
                                    : Icons.play_circle_outline,
                              ),
                              label: Text(playing ? 'Pause' : 'Resume'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.10,
                                ),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _selectedBeat == null
                        ? 'No beat selected'
                        : 'Selected: ${_selectedBeat!.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startSelectedBeatAndClose() async {
    final beat = _selectedBeat;
    if (beat == null) return;
    if (_beatBusy) return;

    setState(() => _beatBusy = true);
    try {
      final audioUrl = await beat.resolveAudioUrl(Supabase.instance.client);
      if (!mounted) return;
      if (audioUrl == null || audioUrl.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Beat audio not available.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
        return;
      }

      final filePath = await BeatDownloadService().downloadMp3(
        url: audioUrl,
        fileNameStem: 'solo_${beat.id}',
      );
      if (!mounted) return;

      final ok = await _streamController.startBackgroundBeat(
        filePath: filePath,
        publishVolumePercent: 55,
        playoutVolumePercent: 65,
        loop: true,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start beat.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
        return;
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e)),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _beatBusy = false);
    }
  }

  void _openGiftsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return GiftSelectionSheet(
          competitor1Id: _hostId,
          competitor1Name: widget.hostName,
          competitor2Id: '',
          competitor2Name: '',
          onGiftSelected: (gift, toHostId) {
            // Host UI: sending gifts isn't typical, but this keeps the sheet usable for QA.
            // For received gifts, we rely on realtime.
            _giftController.sendGift(gift);
          },
        );
      },
    );
  }

  Future<void> _confirmEndLive() async {
    if (_ending) return;

    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: Colors.black,
              title: const Text(
                'End live?',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Your live stream will stop for everyone.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'End',
                    style: TextStyle(color: WeAfricaColors.error),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm || !mounted) return;
    await _endLive();
  }

  Future<void> _endLive() async {
    if (_ending) return;

    setState(() => _ending = true);
    try {
      await _streamController.stopBackgroundBeat();
      await _streamController.leaveChannel();

      await LiveSessionService().endLiveAndEnsureCleared(
        hostId: _hostId,
        channelId: widget.channelId,
      );

      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e)),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the stream running; just reduce UI load.
    if (state == AppLifecycleState.paused) {
      _energy.value = (_energy.value * 0.9).clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _viewerSub?.cancel();
    _scoreSub?.cancel();
    _giftSub?.cancel();
    _chatSub?.cancel();

    _heartbeatTimer?.cancel();
    _energyTimer?.cancel();
    _bigGiftTimer?.cancel();

    unawaited(_realtime.dispose());
    _giftController.dispose();
    _streamController.dispose();
    _energy.dispose();

    super.dispose();
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(
          child: CircularProgressIndicator(color: WeAfricaColors.gold),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: WeAfricaColors.error,
                  size: 42,
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initialize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WeAfricaColors.gold,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LiveStreamController>.value(
          value: _streamController,
        ),
        ChangeNotifierProvider<GiftController>.value(value: _giftController),
      ],
      child: Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _addHeart,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _SoloVideoStage(
                engine: _streamController.engine,
                channelId: widget.channelId,
                localVideoEnabled: _localVideoEnabled,
              ),

              // Readability gradient.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RowTopBar(
                        viewerCountLabel: _formatCount(_viewerCount),
                        diamondsLabel: _formatCount(_diamonds),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: _GoalCard(
                            title: 'Diamond Goal',
                            value: _diamonds,
                            target: _diamondGoalTarget,
                          ),
                        ),
                      ),
                      const Spacer(),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ChatOverlay(messages: _recentMessages),
                      ),
                      const SizedBox(height: 12),
                      _BottomControlBar(
                        micMuted: _micMuted,
                        onMicTap: _ending ? null : _toggleMic,
                        onBeatTap: _ending ? null : _openBeatSelector,
                        onCameraTap: _ending ? null : _toggleCamera,
                        onSwitchCamera: _ending ? null : _switchCamera,
                        onGiftsTap: _ending ? null : _openGiftsSheet,
                        onEndTap: _ending ? null : _confirmEndLive,
                        ending: _ending,
                      ),
                    ],
                  ),
                ),
              ),

              // Hearts + gifts.
              FloatingHeartsLayer(hearts: _hearts),
              const GiftAnimationOverlay(),

              if (_bigGift != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 90,
                  child: _BigGiftPopup(gift: _bigGift!),
                ),

              if (_ending)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: WeAfricaColors.gold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoloVideoStage extends StatelessWidget {
  const _SoloVideoStage({
    required this.engine,
    required this.channelId,
    required this.localVideoEnabled,
  });

  final RtcEngine? engine;
  final String channelId;
  final bool localVideoEnabled;

  @override
  Widget build(BuildContext context) {
    final rtcEngine = engine;
    if (rtcEngine == null) {
      return Container(
        color: WeAfricaColors.deepIndigo,
        child: const Center(
          child: CircularProgressIndicator(color: WeAfricaColors.gold),
        ),
      );
    }

    if (!localVideoEnabled) {
      return Container(
        color: WeAfricaColors.deepIndigo,
        child: Center(
          child: Icon(
            Icons.videocam_off,
            size: 54,
            color: WeAfricaColors.gold.withValues(alpha: 0.35),
          ),
        ),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: rtcEngine,
        canvas: const VideoCanvas(uid: 0),
        useFlutterTexture: !kIsWeb,
      ),
      onAgoraVideoViewCreated: (_) {
        unawaited(rtcEngine.startPreview());
      },
    );
  }
}

class _RowTopBar extends StatelessWidget {
  const _RowTopBar({
    required this.viewerCountLabel,
    required this.diamondsLabel,
  });

  final String viewerCountLabel;
  final String diamondsLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: WeAfricaColors.error.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: WeAfricaColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.people, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  viewerCountLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.diamond, color: WeAfricaColors.gold, size: 18),
                const SizedBox(width: 6),
                Text(
                  diamondsLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'SOLO',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.title,
    required this.value,
    required this.target,
  });

  final String title;
  final int value;
  final int target;

  @override
  Widget build(BuildContext context) {
    final pct = (value / target).clamp(0.0, 1.0);
    final left = (target - value).clamp(0, target);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '$value / $target',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(
                WeAfricaColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            left == 0 ? 'Goal reached!' : '$left left to hit the goal',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatOverlay extends StatelessWidget {
  const _ChatOverlay({required this.messages});

  final List<ChatMessageModel> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 320,
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: messages
              .map((m) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${m.userName}: ',
                          style: const TextStyle(
                            color: WeAfricaColors.gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: m.message,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _BottomControlBar extends StatelessWidget {
  const _BottomControlBar({
    required this.micMuted,
    required this.onMicTap,
    required this.onBeatTap,
    required this.onCameraTap,
    required this.onSwitchCamera,
    required this.onGiftsTap,
    required this.onEndTap,
    required this.ending,
  });

  final bool micMuted;
  final Future<void> Function()? onMicTap;
  final VoidCallback? onBeatTap;
  final Future<void> Function()? onCameraTap;
  final Future<void> Function()? onSwitchCamera;
  final VoidCallback? onGiftsTap;
  final Future<void> Function()? onEndTap;
  final bool ending;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _ControlButton(
              icon: micMuted ? Icons.mic_off : Icons.mic,
              label: micMuted ? 'Mic Off' : 'Mic',
              onTap: onMicTap == null ? null : () => unawaited(onMicTap!()),
              highlight: micMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ControlButton(
              icon: Icons.music_note,
              label: 'Beat',
              onTap: onBeatTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ControlButton(
              icon: Icons.cameraswitch,
              label: 'Camera',
              onTap: onSwitchCamera == null
                  ? null
                  : () => unawaited(onSwitchCamera!()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ControlButton(
              icon: Icons.card_giftcard,
              label: 'Gifts',
              onTap: onGiftsTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ControlButton(
              icon: Icons.close,
              label: ending ? 'Ending…' : 'End',
              onTap: onEndTap == null ? null : () => unawaited(onEndTap!()),
              accent: WeAfricaColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accent;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final baseColor = (accent ?? WeAfricaColors.gold);
    final fg = isDisabled
        ? Colors.white38
        : (accent != null ? Colors.white : Colors.white);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: highlight
              ? baseColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                (highlight ? baseColor : Colors.white.withValues(alpha: 0.12))
                    .withValues(alpha: isDisabled ? 0.4 : 1.0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _BigGiftPopup extends StatelessWidget {
  const _BigGiftPopup({required this.gift});

  final GiftModel gift;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: gift.color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gift.color.withValues(alpha: 0.35)),
            ),
            child: Icon(gift.icon, color: gift.color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gift.senderName.trim().isEmpty ? 'Fan' : gift.senderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'sent ${gift.displayName}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: WeAfricaColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '+${gift.scoreValue}',
              style: const TextStyle(
                color: WeAfricaColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FloatingHeart extends StatefulWidget {
  const FloatingHeart({super.key, required this.onComplete});

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
              child: const Icon(
                Icons.favorite,
                color: Colors.redAccent,
                size: 20,
              ),
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
  const FloatingHeartsLayer({super.key, required this.hearts});

  final List<FloatingHeart> hearts;

  @override
  Widget build(BuildContext context) {
    if (hearts.isEmpty) return const SizedBox.shrink();
    return Stack(children: hearts);
  }
}
