import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../live/services/battle_matching_api.dart';
import '../../live/screens/professional_battle_screen.dart';
import '../../live/services/battle_status_service.dart';
import '../../live/services/live_session_service.dart';

class WaitingForOpponentScreen extends StatefulWidget {
  const WaitingForOpponentScreen({
    super.key,
    required this.battleId,
    required this.channelId,
    required this.battleTitle,
    required this.opponentId,
    required this.hostId,
    required this.hostName,
    this.beatId,
    this.beatName,
  });

  final String battleId;
  final String channelId;
  final String battleTitle;
  final String opponentId;
  final String hostId;
  final String hostName;
  final String? beatId;
  final String? beatName;

  @override
  State<WaitingForOpponentScreen> createState() => _WaitingForOpponentScreenState();
}

class _WaitingForOpponentScreenState extends State<WaitingForOpponentScreen> {
  static const BattleMatchingApi _matchingApi = BattleMatchingApi();

  Timer? _pollTimer;
  bool _starting = false;
  bool _isAccepted = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStatus());
    unawaited(_checkStatus());
  }

  Future<void> _checkStatus() async {
    if (_starting) return;

    final bid = widget.battleId.trim();
    if (bid.isEmpty) return;

    final res = await BattleStatusService().fetchStatus(battleId: bid);
    final status = res.data;
    if (!mounted || status == null) return;

    final hostB = status.hostBId.trim();
    final expectedOpponent = widget.opponentId.trim();

    final opponentMatched = expectedOpponent.isEmpty || (hostB.isNotEmpty && hostB == expectedOpponent);

    final inviteAccepted = await _isInviteAcceptedByOpponent(
      battleId: bid,
      expectedOpponentId: expectedOpponent,
    );

    // Important: invite acceptance does not always flip live_battles.status to `live` immediately.
    // If we wait only for status.isLive, host A can get stuck on the waiting screen.
    final accepted = inviteAccepted || (opponentMatched && status.isLive);

    if (accepted && !_isAccepted) {
      setState(() => _isAccepted = true);
      await _startBattle(
        channelId: status.channelId.trim().isNotEmpty ? status.channelId.trim() : widget.channelId.trim(),
        durationSeconds: status.durationSeconds ?? 300,
        opponentId: hostB.isNotEmpty ? hostB : expectedOpponent,
      );
    }
  }

  Future<bool> _isInviteAcceptedByOpponent({
    required String battleId,
    required String expectedOpponentId,
  }) async {
    try {
      final accepted = await _matchingApi.listInvites(
        box: 'outbox',
        status: 'accepted',
        limit: 50,
      );

      for (final inv in accepted) {
        final sameBattle = inv.battleId.trim() == battleId;
        if (!sameBattle) continue;

        if (expectedOpponentId.isEmpty) return true;

        final toUid = inv.toUid.trim();
        if (toUid == expectedOpponentId) return true;
      }
    } catch (_) {
      // best-effort fallback; status.isLive check still applies.
    }
    return false;
  }

  Future<({String name, String type, String? avatarUrl})> _resolveOpponentProfile(String opponentId) async {
    final id = opponentId.trim();
    if (id.isEmpty) return (name: 'Opponent', type: 'artist', avatarUrl: null);

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, role')
          .eq('id', id)
          .maybeSingle();

      if (row == null) return (name: 'Opponent', type: 'artist', avatarUrl: null);

      final username = (row['username'] ?? '').toString().trim();
      final display = (row['display_name'] ?? '').toString().trim();
      final role = (row['role'] ?? '').toString().trim();
      final avatar = (row['avatar_url'] ?? '').toString().trim();

      final resolvedName = display.isNotEmpty ? display : (username.isNotEmpty ? '@$username' : 'Opponent');
      final resolvedType = role.isNotEmpty ? role : 'artist';
      final resolvedAvatar = avatar.isNotEmpty ? avatar : null;

      return (name: resolvedName, type: resolvedType, avatarUrl: resolvedAvatar);
    } catch (_) {
      return (name: 'Opponent', type: 'artist', avatarUrl: null);
    }
  }

  Future<void> _startBattle({
    required String channelId,
    required int durationSeconds,
    required String opponentId,
  }) async {
    if (_starting) return;
    setState(() => _starting = true);

    try {
      final joinRes = await LiveSessionService().joinSession(
        channelId,
        widget.hostId,
        asBroadcaster: true,
        battleId: widget.battleId,
      );
      final session = joinRes.data;

      if (!mounted || session == null) {
        setState(() => _starting = false);
        return;
      }

      final opponentProfile = await _resolveOpponentProfile(opponentId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProfessionalBattleScreen(
            sessionId: session.id,
            liveId: session.liveId,
            battleId: widget.battleId,
            competitor1Id: widget.hostId,
            competitor2Id: opponentId,
            competitor1Name: widget.hostName,
            competitor2Name: opponentProfile.name,
            competitor1Type: 'artist',
            competitor2Type: opponentProfile.type,
            durationSeconds: durationSeconds,
            currentUserId: widget.hostId,
            currentUserName: widget.hostName,
            channelId: session.channelId,
            token: session.token,
            agoraUid: _stableAgoraUid(widget.hostId),
            competitor2AvatarUrl: opponentProfile.avatarUrl,
            autoPromptInviteOnStart: opponentId.trim().isEmpty,
            initialBeatId: (widget.beatId ?? '').trim().isEmpty ? null : widget.beatId,
            initialBeatName: (widget.beatName ?? '').trim().isEmpty ? null : widget.beatName,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start battle right now.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  int _stableAgoraUid(String userId) {
    final h = userId.hashCode.abs();
    final uid = (h % 2000000000);
    return uid == 0 ? 1 : uid;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        appBar: AppBar(
          title: const Text('Waiting for Opponent'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: WeAfricaColors.goldWithOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: _starting
                        ? const Icon(Icons.play_circle_fill, color: WeAfricaColors.gold, size: 60)
                        : const CircularProgressIndicator(
                            color: WeAfricaColors.gold,
                            strokeWidth: 3,
                          ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  widget.battleTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _isAccepted ? 'Opponent accepted. Starting…' : 'Waiting for opponent to accept…',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Invite your opponent from the battle dashboard',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => Navigator.popUntil(
                    context,
                    (route) => route.isFirst,
                  ),
                  child: Text(
                    'Cancel Battle',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
