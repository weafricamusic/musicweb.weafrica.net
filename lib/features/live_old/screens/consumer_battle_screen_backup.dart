import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../../app/utils/user_facing_error.dart';
import '../controllers/battle_controller.dart';
import '../controllers/gift_controller.dart';
import '../controllers/live_stream_controller.dart';
import '../models/battle_status.dart';
import '../models/gift_model.dart';
import '../models/live_session_model.dart';
import '../services/battle_interactions_service.dart';
import '../services/battle_status_service.dart';
import '../services/gift_service.dart';
import '../services/live_economy_api.dart';
import '../services/live_realtime_service.dart';
import '../widgets/battle/battle_score_board.dart';
import '../widgets/battle/battle_split_view.dart';
import '../widgets/battle/battle_timer.dart';
import '../widgets/gift/gift_animation_overlay.dart';
import '../widgets/gift/gift_selection_sheet.dart';

class ConsumerBattleScreen extends StatefulWidget {
  const ConsumerBattleScreen({
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
    this.onBattleEnded,
    this.competitor1AvatarUrl,
    this.competitor2AvatarUrl,
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
  final VoidCallback? onBattleEnded;
  final String? competitor1AvatarUrl;
  final String? competitor2AvatarUrl;

  @override
  State<ConsumerBattleScreen> createState() => _ConsumerBattleScreenState();
}

class _ConsumerBattleScreenState extends State<ConsumerBattleScreen> {
  static const Color _grassBase = Color(0xFF07150B);
  static const Color _grassShade = Color(0xFF0E2414);
  static const Color _grassMid = Color(0xFF15361E);
  static const Color _grassAccent = Color(0xFF2F9B57);
  static const Color _grassGlow = Color(0xFF7EE08A);

  late final LiveStreamController _streamController;
  late final BattleController _battleController;
  late final GiftController _giftController;
  late final LiveRealtimeService _realtimeService;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  StreamSubscription<int>? _viewerCountSub;
  StreamSubscription<int>? _giftCountSub;
  StreamSubscription<Map<String, int>>? _scoreSub;
  StreamSubscription<GiftModel>? _giftSub;
  Timer? _statusTimer;
  Timer? _giftPulseHideTimer;

  bool _isLoading = true;
  bool _sendBusy = false;
  bool _giftBusy = false;
  bool _showResults = false;
  bool _resultsDismissed = false;
  String? _error;
  String? _giftPulseText;
  BattleStatus? _battleStatus;
  int _viewerCount = 0;
  int _giftCount = 0;
  int? _coinBalance;
  bool _didNotifyBattleEnded = false;

  String get _battleId {
    final direct = (widget.battleId ?? '').trim();
    if (direct.isNotEmpty) return direct;
    final channel = widget.channelId.trim();
    const prefix = 'weafrica_battle_';
    if (channel.startsWith(prefix)) return channel.substring(prefix.length).trim();
    return channel;
  }

  bool get _isSignedIn => FirebaseAuth.instance.currentUser != null;

  String get _safeCompetitor2Name {
    final name = widget.competitor2Name.trim();
    return name.isNotEmpty ? name : 'Opponent';
  }

  bool get _battleEnded => (_battleStatus?.isEnded ?? false) || (_battleController.timeRemaining == 0);

  @override
  void initState() {
    super.initState();
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

    unawaited(_initialize());
  }

  @override
  void dispose() {
    _viewerCountSub?.cancel();
    _giftCountSub?.cancel();
    _scoreSub?.cancel();
    _giftSub?.cancel();
    _statusTimer?.cancel();
    _giftPulseHideTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _streamController.dispose();
    _battleController.dispose();
    _giftController.dispose();
    unawaited(_realtimeService.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      debugPrint(
        'CONSUMER_INIT battle liveId=${widget.liveId} battleId=$_battleId channel=${widget.channelId} uid=${widget.agoraUid} tokenLen=${widget.token.length}',
      );

      final streamOk = await _streamController.initialize(
        channelId: widget.channelId,
        token: widget.token,
        role: UserRole.audience,
        uid: widget.agoraUid,
      );

      debugPrint(
        streamOk
            ? 'CONSUMER_INIT battle stream joined: channel=${widget.channelId} uid=${widget.agoraUid}'
            : 'CONSUMER_INIT battle stream failed: channel=${widget.channelId} uid=${widget.agoraUid}',
      );

      if (!streamOk) {
        throw StateError('Could not start battle viewer stream.');
      }

      await _battleController.connectToBattle(_battleId);
      await _realtimeService.connect();

      _viewerCountSub = _realtimeService.viewerCountStream.listen((count) {
        if (!mounted) return;
        setState(() => _viewerCount = count);
      });

      _giftCountSub = _realtimeService.totalGiftsStream.listen((count) {
        if (!mounted) return;
        setState(() => _giftCount = count);
      });

      _scoreSub = _realtimeService.scoreStream.listen((scores) {
        _battleController.applyRealtimeScores(scores);
      });

      _giftSub = _realtimeService.giftStream.listen((gift) {
        _giftController.receiveGift(gift);
        _showGiftPulse(gift);
      });

      await _refreshCoinBalance();
      await _refreshBattleStatus();

      _statusTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_refreshBattleStatus()),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, st) {
      UserFacingError.log('ConsumerBattleScreen._initialize', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Could not open this battle right now.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshCoinBalance() async {
    final balance = await LiveEconomyApi().fetchMyCoinBalance();
    if (!mounted) return;
    setState(() => _coinBalance = balance);
  }

  Future<void> _refreshBattleStatus() async {
    final battleId = _battleId;
    if (battleId.isEmpty) return;

    final res = await BattleStatusService().fetchStatus(battleId: battleId);
    if (!mounted) return;

    res.when(
      success: (status) {
        final shouldShow = !_resultsDismissed && status.isEnded;
        setState(() {
          _battleStatus = status;
          _showResults = shouldShow;
        });
        if (status.isEnded) {
          _notifyBattleEndedOnce();
        }
      },
      loading: () {},
      error: () {},
    );
  }

  void _handleBattleEnded() {
    if (!mounted) return;
    setState(() {
      if (!_resultsDismissed) {
        _showResults = true;
      }
    });
    unawaited(_refreshBattleStatus());
    _notifyBattleEndedOnce();
  }

  void _notifyBattleEndedOnce() {
    if (_didNotifyBattleEnded) return;
    _didNotifyBattleEnded = true;
    widget.onBattleEnded?.call();
  }

  void _showGiftPulse(GiftModel gift) {
    final isBoosted = gift.scoreValue > gift.coinValue;
    final pulse = isBoosted
        ? '${gift.senderName} sent ${gift.coinValue} coins. 2x score live.'
        : '${gift.senderName} sent ${gift.coinValue} coins.';

    _giftPulseHideTimer?.cancel();
    if (!mounted) return;
    setState(() => _giftPulseText = pulse);
    _giftPulseHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _giftPulseText = null);
    });
  }

  Future<void> _sendGift(GiftModel gift, String toHostId) async {
    if (_giftBusy) return;
    if (!_isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to send gifts.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    setState(() => _giftBusy = true);
    final res = await GiftService().sendGift(
      channelId: widget.channelId,
      toHostId: toHostId,
      giftId: gift.id,
      senderName: widget.currentUserName,
      liveId: widget.liveId,
    );
    if (!mounted) return;

    res.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _battleController.isUrgent
                  ? 'Gift sent. Final 10 seconds score is boosted.'
                  : 'Gift sent.',
            ),
            backgroundColor: WeAfricaColors.success,
          ),
        );
        unawaited(_refreshCoinBalance());
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

    setState(() => _giftBusy = false);
  }

  void _openGiftSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GiftSelectionSheet(
        competitor1Id: widget.competitor1Id,
        competitor1Name: widget.competitor1Name,
        competitor2Id: widget.competitor2Id,
        competitor2Name: _safeCompetitor2Name,
        onGiftSelected: (gift, toHostId) => unawaited(_sendGift(gift, toHostId)),
      ),
    );
  }

  Future<void> _sendChat() async {
    if (_sendBusy) return;
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    if (!_isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to chat.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    setState(() => _sendBusy = true);
    final res = await BattleInteractionsService().sendChatMessage(
      battleId: _battleId,
      userId: widget.currentUserId,
      userName: widget.currentUserName,
      message: message,
    );
    if (!mounted) return;

    res.when(
      success: (_) {
        _chatController.clear();
      },
      loading: () {},
      error: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send message.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
      },
    );

    setState(() => _sendBusy = false);
  }

  String _winnerHeadline(BattleStatus? status) {
    if (status?.isDraw == true) return 'Battle drawn';
    final winnerId = status?.winnerUid?.trim();
    if (winnerId == widget.competitor1Id.trim()) return '${widget.competitor1Name} takes it';
    if (winnerId == widget.competitor2Id.trim()) return '$_safeCompetitor2Name takes it';
    return 'Battle ended';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
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
        body: Stack(
          children: [
            const _GrassBattleBackdrop(),
            SafeArea(
              child: Consumer<BattleController>(
                builder: (context, battle, _) {
                  final leftLeading = battle.competitor1Score > battle.competitor2Score;
                  final rightLeading = battle.competitor2Score > battle.competitor1Score;

                  return Column(
                    children: [
                      _BattleHeader(
                        viewerCount: _viewerCount,
                        giftCount: _giftCount,
                        coinBalance: _coinBalance,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: _BroadcastTicker(
                          viewerCount: _viewerCount,
                          giftCount: _giftCount,
                          urgent: battle.isUrgent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: BattleScoreBoard(
                          competitor1Name: widget.competitor1Name,
                          competitor2Name: _safeCompetitor2Name,
                          score1: battle.competitor1Score,
                          score2: battle.competitor2Score,
                          competitor1Type: widget.competitor1Type,
                          competitor2Type: widget.competitor2Type,
                          isWinning1: leftLeading,
                          isWinning2: rightLeading,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: _ArenaIdentityBar(
                          competitor1Name: widget.competitor1Name,
                          competitor2Name: _safeCompetitor2Name,
                          competitor1Leading: leftLeading,
                          competitor2Leading: rightLeading,
                          urgent: battle.isUrgent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: BattleTimer(
                                timeRemaining: battle.timeRemaining,
                                progress: battle.progress,
                                isUrgent: battle.isUrgent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _BattlePulseBadge(
                              active: battle.isUrgent,
                              label: battle.isUrgent ? 'power play 2x' : 'broadcast live',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _BattleStageCard(
                            child: BattleSplitView(
                              competitor1Name: widget.competitor1Name,
                              competitor2Name: _safeCompetitor2Name,
                              competitor1Type: widget.competitor1Type,
                              competitor2Type: widget.competitor2Type,
                              isCompetitor1Leading: leftLeading,
                              isCompetitor2Leading: rightLeading,
                              channelId: widget.channelId,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 760;
                            final intel = _BattleIntelCard(
                              status: _battleStatus,
                              battleEnded: _battleEnded,
                              headline: _winnerHeadline(_battleStatus),
                            );
                            final support = _SupportDeckCard(
                              battleId: _battleId,
                              competitor1Id: widget.competitor1Id,
                              competitor2Id: widget.competitor2Id,
                              currentUserId: widget.currentUserId,
                              signedIn: _isSignedIn,
                              competitor1Name: widget.competitor1Name,
                              competitor2Name: _safeCompetitor2Name,
                              battleEnded: _battleEnded,
                              giftBusy: _giftBusy,
                              showResults: _showResults,
                              hasStatus: _battleStatus != null,
                              onGift: _openGiftSheet,
                              onResults: () {
                                setState(() {
                                  _showResults = true;
                                  _resultsDismissed = false;
                                });
                              },
                            );

                            if (compact) {
                              return Column(
                                children: [
                                  intel,
                                  const SizedBox(height: 12),
                                  support,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: intel),
                                const SizedBox(width: 12),
                                Expanded(child: support),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: _BattleChatCard(
                            battleId: _battleId,
                            controller: _chatController,
                            scrollController: _chatScrollController,
                            sendBusy: _sendBusy,
                            enabled: !_battleEnded,
                            onSend: _sendChat,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: GiftAnimationOverlay())),
            if (_giftPulseText != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: _GiftPulseBanner(text: _giftPulseText!),
              ),
            if (_showResults && _battleStatus != null)
              _BattleResultsOverlay(
                status: _battleStatus!,
                competitor1Name: widget.competitor1Name,
                competitor2Name: _safeCompetitor2Name,
                onDismiss: () {
                  setState(() {
                    _showResults = false;
                    _resultsDismissed = true;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _GrassBattleBackdrop extends StatelessWidget {
  const _GrassBattleBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _ConsumerBattleScreenState._grassBase,
                _ConsumerBattleScreenState._grassShade,
                _ConsumerBattleScreenState._grassMid,
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -40,
          child: _GlowOrb(
            size: 260,
            color: _ConsumerBattleScreenState._grassGlow.withValues(alpha: 0.15),
          ),
        ),
        Positioned(
          right: -80,
          top: 180,
          child: _GlowOrb(
            size: 240,
            color: WeAfricaColors.gold.withValues(alpha: 0.08),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PitchLinesPainter(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(Offset(size.width / 2, size.height * 0.42), 56, centerPaint);
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BattleHeader extends StatelessWidget {
  const _BattleHeader({
    required this.viewerCount,
    required this.giftCount,
    required this.coinBalance,
    required this.onBack,
  });

  final int viewerCount;
  final int giftCount;
  final int? coinBalance;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matchday Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Head-to-head battle broadcast with live crowd scoring',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          _HeaderPill(icon: Icons.visibility_outlined, label: '$viewerCount'),
          const SizedBox(width: 8),
          _HeaderPill(icon: Icons.local_fire_department_outlined, label: '$giftCount'),
          const SizedBox(width: 8),
          _HeaderPill(icon: Icons.monetization_on_outlined, label: coinBalance?.toString() ?? '—'),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: WeAfricaColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BroadcastTicker extends StatelessWidget {
  const _BroadcastTicker({
    required this.viewerCount,
    required this.giftCount,
    required this.urgent,
  });

  final int viewerCount;
  final int giftCount;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TickerChip(label: 'Signal', value: 'Live'),
          _TickerChip(label: 'Audience', value: '$viewerCount'),
          _TickerChip(label: 'Gifts', value: '$giftCount'),
          _TickerChip(label: 'Scoring', value: urgent ? '2x power play' : 'Standard'),
        ],
      ),
    );
  }
}

class _TickerChip extends StatelessWidget {
  const _TickerChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattlePulseBadge extends StatelessWidget {
  const _BattlePulseBadge({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bg = active ? _ConsumerBattleScreenState._grassAccent : Colors.white.withValues(alpha: 0.08);
    final fg = active ? Colors.white : Colors.white70;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: active ? 0.16 : 0.08)),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _ConsumerBattleScreenState._grassGlow.withValues(alpha: 0.24),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: fg, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}

class _ArenaIdentityBar extends StatelessWidget {
  const _ArenaIdentityBar({
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Leading,
    required this.competitor2Leading,
    required this.urgent,
  });

  final String competitor1Name;
  final String competitor2Name;
  final bool competitor1Leading;
  final bool competitor2Leading;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ArenaSideChip(
              name: competitor1Name,
              active: competitor1Leading,
              accent: const Color(0xFF4DA6FF),
              alignment: CrossAxisAlignment.start,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  urgent ? 'POWER PLAY' : 'MAIN EVENT',
                  style: TextStyle(
                    color: urgent ? WeAfricaColors.gold : Colors.white70,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: urgent
                        ? WeAfricaColors.gold.withValues(alpha: 0.18)
                        : _ConsumerBattleScreenState._grassAccent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ArenaSideChip(
              name: competitor2Name,
              active: competitor2Leading,
              accent: const Color(0xFFFF7568),
              alignment: CrossAxisAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArenaSideChip extends StatelessWidget {
  const _ArenaSideChip({
    required this.name,
    required this.active,
    required this.accent,
    required this.alignment,
  });

  final String name;
  final bool active;
  final Color accent;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          active ? 'MOMENTUM' : 'ON STAGE',
          style: TextStyle(
            color: active ? accent : Colors.white54,
            fontWeight: FontWeight.w900,
            fontSize: 10,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: active ? FontWeight.w900 : FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _BattleStageCard extends StatelessWidget {
  const _BattleStageCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleIntelCard extends StatelessWidget {
  const _BattleIntelCard({
    required this.status,
    required this.battleEnded,
    required this.headline,
  });

  final BattleStatus? status;
  final bool battleEnded;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final totalSpentCoins = status?.totalSpentCoins ?? 0;
    final topGifters = status?.topGifters ?? const <BattleTopGifter>[];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.grid_view, color: _ConsumerBattleScreenState._grassGlow, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  battleEnded ? headline : 'Match center',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IntelChip(label: 'Pot', value: '$totalSpentCoins coins'),
                    _IntelChip(label: 'Scoring', value: battleEnded ? 'Locked' : 'Server scored'),
                    _IntelChip(label: 'Status', value: battleEnded ? 'Final whistle' : 'In play'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  topGifters.isEmpty
                      ? 'No support leaders locked yet.'
                      : 'Support leaders: ${topGifters.take(2).map((g) => g.senderName).join(' • ')}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntelChip extends StatelessWidget {
  const _IntelChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SupportDeckCard extends StatelessWidget {
  const _SupportDeckCard({
    required this.battleId,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.currentUserId,
    required this.signedIn,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.battleEnded,
    required this.giftBusy,
    required this.showResults,
    required this.hasStatus,
    required this.onGift,
    required this.onResults,
  });

  final String battleId;
  final String competitor1Id;
  final String competitor2Id;
  final String currentUserId;
  final bool signedIn;
  final String competitor1Name;
  final String competitor2Name;
  final bool battleEnded;
  final bool giftBusy;
  final bool showResults;
  final bool hasStatus;
  final VoidCallback onGift;
  final VoidCallback onResults;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Support desk',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Back a side, trigger gifting, then monitor the board. This is a live match desk, not a social tray.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SupportTargetChip(name: competitor1Name, accent: const Color(0xFF4DA6FF))),
              const SizedBox(width: 10),
              Expanded(child: _SupportTargetChip(name: competitor2Name, accent: const Color(0xFFFF7568))),
            ],
          ),
          const SizedBox(height: 12),
          _BattleVotePanel(
            battleId: battleId,
            competitor1Id: competitor1Id,
            competitor2Id: competitor2Id,
            competitor1Name: competitor1Name,
            competitor2Name: competitor2Name,
            currentUserId: currentUserId,
            signedIn: signedIn,
            enabled: !battleEnded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: battleEnded || giftBusy ? null : onGift,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ConsumerBattleScreenState._grassAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: giftBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.card_giftcard),
                  label: Text(battleEnded ? 'Battle ended' : 'Open support desk'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: showResults && hasStatus ? onResults : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Match report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BattleVotePanel extends StatefulWidget {
  const _BattleVotePanel({
    required this.battleId,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.currentUserId,
    required this.signedIn,
    required this.enabled,
  });

  final String battleId;
  final String competitor1Id;
  final String competitor2Id;
  final String competitor1Name;
  final String competitor2Name;
  final String currentUserId;
  final bool signedIn;
  final bool enabled;

  @override
  State<_BattleVotePanel> createState() => _BattleVotePanelState();
}

class _BattleVotePanelState extends State<_BattleVotePanel> {
  bool _busy = false;

  String _s(String value) => value.trim();

  Future<void> _voteFor(String competitorId) async {
    if (_busy) return;
    if (!widget.enabled) return;

    if (!widget.signedIn || _s(widget.currentUserId).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to vote.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    final battleId = _s(widget.battleId);
    final userId = _s(widget.currentUserId);
    final target = _s(competitorId);
    if (battleId.isEmpty || userId.isEmpty || target.isEmpty) return;

    setState(() => _busy = true);
    try {
      final res = await BattleInteractionsService().castVote(
        battleId: battleId,
        userId: userId,
        votedFor: target,
      );

      if (!mounted) return;
      res.when(
        success: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vote locked in.'),
              backgroundColor: WeAfricaColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        },
        loading: () {},
        error: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not cast vote.'),
              backgroundColor: WeAfricaColors.error,
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final battleId = _s(widget.battleId);
    final c1 = _s(widget.competitor1Id);
    final c2 = _s(widget.competitor2Id);

    if (battleId.isEmpty || c1.isEmpty || c2.isEmpty) {
      return const SizedBox.shrink();
    }

    final votesStream = BattleInteractionsService().watchVoteSummary(
      battleId: battleId,
      competitor1Id: c1,
      competitor2Id: c2,
      currentUserId: _s(widget.currentUserId),
    );

    return StreamBuilder<BattleVoteSummary>(
      stream: votesStream,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        final votes1 = summary?.competitor1Votes ?? 0;
        final votes2 = summary?.competitor2Votes ?? 0;
        final myVote = (summary?.myVote ?? '').trim();

        final c1Selected = myVote.isNotEmpty && myVote == c1;
        final c2Selected = myVote.isNotEmpty && myVote == c2;

        final disabled = _busy || !widget.enabled;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.how_to_vote_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Vote',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    'Votes $votes1-$votes2',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: disabled ? null : () => _voteFor(c1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: c1Selected ? const Color(0xFF4DA6FF).withValues(alpha: 0.18) : null,
                        side: BorderSide(
                          color: (c1Selected ? const Color(0xFF4DA6FF) : Colors.white.withValues(alpha: 0.16)),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: Text(
                        c1Selected ? 'Voted ${widget.competitor1Name}' : 'Vote ${widget.competitor1Name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: disabled ? null : () => _voteFor(c2),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: c2Selected ? const Color(0xFFFF7568).withValues(alpha: 0.16) : null,
                        side: BorderSide(
                          color: (c2Selected ? const Color(0xFFFF7568) : Colors.white.withValues(alpha: 0.16)),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: Text(
                        c2Selected ? 'Voted ${widget.competitor2Name}' : 'Vote ${widget.competitor2Name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (!widget.enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Voting closed.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SupportTargetChip extends StatelessWidget {
  const _SupportTargetChip({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Support target',
            style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BattleChatCard extends StatelessWidget {
  const _BattleChatCard({
    required this.battleId,
    required this.controller,
    required this.scrollController,
    required this.sendBusy,
    required this.enabled,
    required this.onSend,
  });

  final String battleId;
  final TextEditingController controller;
  final ScrollController scrollController;
  final bool sendBusy;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: WeAfricaColors.gold, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Commentary line',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  enabled ? 'live' : 'locked',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.52), fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<BattleChatEntry>>(
              stream: BattleInteractionsService().watchChat(battleId: battleId, limit: 40),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? const <BattleChatEntry>[];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No commentary yet. Crowd calls and reactions will land here.',
                      style: TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final entry = messages[index];
                    final own = entry.userId.trim() == (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: own
                                ? _ConsumerBattleScreenState._grassAccent.withValues(alpha: 0.30)
                                : Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.userName,
                                style: TextStyle(
                                  color: own ? Colors.white : WeAfricaColors.gold,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.message,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !sendBusy,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: enabled ? 'Call the match...' : 'Battle ended',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: enabled ? (_) => onSend() : null,
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: enabled && !sendBusy ? onSend : null,
                  style: IconButton.styleFrom(
                    backgroundColor: _ConsumerBattleScreenState._grassAccent,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                  icon: sendBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftPulseBanner extends StatelessWidget {
  const _GiftPulseBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ConsumerBattleScreenState._grassGlow.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: WeAfricaColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleResultsOverlay extends StatelessWidget {
  const _BattleResultsOverlay({
    required this.status,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.onDismiss,
  });

  final BattleStatus status;
  final String competitor1Name;
  final String competitor2Name;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final winnerId = (status.winnerUid ?? '').trim();
    final title = status.isDraw
        ? 'Draw after the final whistle'
        : (winnerId == status.hostAId.trim() ? '$competitor1Name wins' : '$competitor2Name wins');

    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _ConsumerBattleScreenState._grassShade,
                        Colors.black.withValues(alpha: 0.94),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Battle closed',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _ResultScoreTile(name: competitor1Name, score: status.hostAScore),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ResultScoreTile(name: competitor2Name, score: status.hostBScore),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Top gifters',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (status.topGifters.isEmpty)
                        const Text(
                          'No gifting summary available yet.',
                          style: TextStyle(color: Colors.white54),
                        )
                      else
                        ...status.topGifters.take(3).toList().asMap().entries.map((entry) {
                          final index = entry.key;
                          final gifter = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    gifter.senderName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${gifter.coins} coins',
                                  style: const TextStyle(color: WeAfricaColors.gold, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onDismiss,
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultScoreTile extends StatelessWidget {
  const _ResultScoreTile({required this.name, required this.score});

  final String name;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '$score',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}