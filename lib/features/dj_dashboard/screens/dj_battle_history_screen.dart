import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../services/dj_identity_service.dart';

class DjBattleHistoryScreen extends StatefulWidget {
  const DjBattleHistoryScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjBattleHistoryScreen> createState() => _DjBattleHistoryScreenState();
}

class _DjBattleHistoryScreenState extends State<DjBattleHistoryScreen> {
  final _identity = DjIdentityService();

  late final String _djUid;
  late Future<List<_BattleRow>> _future;

  @override
  void initState() {
    super.initState();
    _djUid = _identity.requireDjUid();
    _future = _load();
  }

  String _pgArrayValue(String value) => value.replaceAll('"', '\\"');

  bool _looksLikeMissingTable(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('pgrst205') || (msg.contains('battles') && msg.contains('does not exist'));
  }

  Future<List<_BattleRow>> _load() async {
    try {
      final uid = _djUid;
      final rows = await Supabase.instance.client
          .from('battles')
          .select(
            'id,title,status,starts_at,started_at,ended_at,prize_pool,winner_id,participant_ids,created_at',
          )
          .or('dj_id.eq.$uid,participant_ids.cs.{${_pgArrayValue(uid)}}')
          .order('created_at', ascending: false)
          .limit(200);

      final list = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(_BattleRow.fromRow)
          .where((b) => b.isHistory)
          .toList(growable: false);

      return list;
    } catch (e) {
      if (_looksLikeMissingTable(e)) {
        return const <_BattleRow>[];
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<_BattleRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load battle history. Please try again.',
            onRetry: _refresh,
          );
        }

        final battles = snap.data ?? const <_BattleRow>[];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              if (battles.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('No completed battles yet'),
                )
              else
                ...battles.map((b) => _BattleTile(battle: b, myUid: _djUid)),
              ],
            ),
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Battle History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _BattleRow {
  const _BattleRow({
    required this.id,
    required this.title,
    required this.status,
    required this.prizePool,
    required this.winnerId,
    required this.participantIds,
    required this.createdAt,
    required this.startsAt,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String title;
  final String status;
  final int prizePool;
  final String winnerId;
  final List<String> participantIds;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isHistory {
    if (endedAt != null) return true;
    final s = status.trim().toLowerCase();
    return s == 'completed' || s == 'ended' || s == 'finished' || s == 'done';
  }

  DateTime get sortTime => (endedAt ?? startedAt ?? startsAt ?? createdAt);

  factory _BattleRow.fromRow(Map<String, dynamic> row) {
    final participantsRaw = row['participant_ids'];
    final participants = <String>[];
    if (participantsRaw is List) {
      for (final p in participantsRaw) {
        final s = (p ?? '').toString().trim();
        if (s.isNotEmpty) participants.add(s);
      }
    }

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '0').toString()) ?? 0;
    }

    DateTime? toDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return _BattleRow(
      id: (row['id'] ?? '').toString(),
      title: ((row['title'] ?? '') as Object).toString().trim().isEmpty
          ? 'Battle'
          : row['title'].toString(),
      status: (row['status'] ?? '').toString(),
      prizePool: toInt(row['prize_pool']),
      winnerId: (row['winner_id'] ?? '').toString(),
      participantIds: participants,
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      startsAt: toDt(row['starts_at']),
      startedAt: toDt(row['started_at']),
      endedAt: toDt(row['ended_at']),
    );
  }
}

class _BattleTile extends StatelessWidget {
  const _BattleTile({required this.battle, required this.myUid});

  final _BattleRow battle;
  final String myUid;

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final base = local.toString().split('.').first;
    return base;
  }

  String _shortId(String id) {
    final s = id.trim();
    if (s.isEmpty) return '—';
    if (s.length <= 10) return s;
    return '${s.substring(0, 10)}…';
  }

  @override
  Widget build(BuildContext context) {
    final winner = battle.winnerId.trim();
    final result = winner.isEmpty
        ? '—'
        : (winner == myUid ? 'WON' : 'LOST');

    final when = _fmt(battle.sortTime);
    final prize = battle.prizePool > 0 ? '${battle.prizePool} coins' : '—';

    final opponents = battle.participantIds.where((p) => p != myUid).toList(growable: false);
    final vs = opponents.isEmpty ? 'Opponent: —' : 'Opponent: ${_shortId(opponents.first)}';

    final status = battle.status.trim().isEmpty ? 'completed' : battle.status.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  battle.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  result,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$when • ${status.toUpperCase()}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(vs, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text('Prize pool: $prize', style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
