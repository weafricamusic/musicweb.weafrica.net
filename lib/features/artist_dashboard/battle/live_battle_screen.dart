import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'battle_models.dart';
import 'battle_results_screen.dart';

class LiveBattleScreen extends StatefulWidget {
  const LiveBattleScreen({super.key, required this.battle});

  final OsBattle battle;

  @override
  State<LiveBattleScreen> createState() => _LiveBattleScreenState();
}

class _LiveBattleScreenState extends State<LiveBattleScreen> {
  late OsBattle _battle;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _battle = widget.battle;

    _syncTimerWithBattleStatus();
  }

  @override
  void didUpdateWidget(covariant LiveBattleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.battle != widget.battle) {
      _battle = widget.battle;
      _syncTimerWithBattleStatus();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _syncTimerWithBattleStatus() {
    if (_battle.status == OsBattleStatus.live) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatTimeLeft(Duration d) {
    if (d.isNegative) return 'Ended';

    String two(int v) => v.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    if (hours > 0) {
      return '$hours ${two(minutes)}m ${two(seconds)}s left';
    }
    return '$minutes ${two(seconds)}s left';
  }

  void _voteYou() {
    if (_battle.status != OsBattleStatus.live) return;
    setState(() {
      _battle = _battle.copyWith(yourVotes: _battle.yourVotes + 1);
    });
  }

  void _voteThem() {
    if (_battle.status != OsBattleStatus.live) return;
    setState(() {
      _battle = _battle.copyWith(opponentVotes: _battle.opponentVotes + 1);
    });
  }

  void _finish() {
    if (_battle.status != OsBattleStatus.live) {
      Navigator.of(context).pop();
      return;
    }

    _stopTimer();

    final won = _battle.yourVotes >= _battle.opponentVotes;
    final completed = _battle.copyWith(
      status: OsBattleStatus.completed,
      result: won ? OsBattleResult.win : OsBattleResult.loss,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => BattleResultsScreen(battle: completed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final live = _battle.status == OsBattleStatus.live;

    final left = _battle.yourVotes;
    final right = _battle.opponentVotes;
    final denom = (left + right).clamp(1, 1 << 30);
    final progress = left / denom;
    final youPct = (progress * 100).round().clamp(0, 100);
    final themPct = (100 - youPct).clamp(0, 100);

    final timeLabel = _formatTimeLeft(_battle.timeLeft);

    return Scaffold(
      appBar: AppBar(
        title: Text(live ? 'LIVE BATTLE' : 'Battle'),
        actions: [
          if (live)
            TextButton(
              onPressed: _finish,
              child: const Text('END'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: live ? cs.error : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live ? cs.error : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      live ? 'LIVE' : _battle.status.name.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: live ? cs.error : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${_battle.stakeCoins} coins',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'YOU vs ${_battle.opponentName.toUpperCase()}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track: ${_battle.trackTitle}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _VotesCard(label: 'You', votes: left, highlight: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _VotesCard(label: 'Them', votes: right, highlight: false),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'You $youPct%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Text(
                      'Them $themPct%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(timeLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                    const Spacer(),
                    Text(
                      'Prize: ${_battle.prizeCoins} coins',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (live) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _voteYou,
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                    label: const Text('Vote You'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _voteThem,
                    icon: const Icon(Icons.thumb_down_alt_outlined),
                    label: const Text('Vote Them'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Tap to vote while the battle is live.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ] else ...[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
          ],
        ),
      ),
    );
  }
}

class _VotesCard extends StatelessWidget {
  const _VotesCard({required this.label, required this.votes, required this.highlight});

  final String label;
  final int votes;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? cs.primary.withValues(alpha: 102) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            votes.toString(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
