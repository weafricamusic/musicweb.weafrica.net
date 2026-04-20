import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';

class DjLeaderboardsScreen extends StatefulWidget {
  const DjLeaderboardsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjLeaderboardsScreen> createState() => _DjLeaderboardsScreenState();
}

class _DjLeaderboardsScreenState extends State<DjLeaderboardsScreen> {
  static const _rankingTypes = <String, String>{
    'coins_earned': 'Coins Earned',
    'gifts_received': 'Gifts Received',
    'battle_wins': 'Battle Wins',
    'followers_growth': 'Followers Growth',
    'view_minutes': 'View Minutes',
  };

  String _rankingType = 'coins_earned';
  late Future<_LeaderboardSnapshot?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  bool _looksLikeNotConfigured(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('pgrst205') || msg.contains('stage_rankings_snapshots');
  }

  Future<Map<String, Map<String, dynamic>>> _bestEffortLoadProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return const <String, Map<String, dynamic>>{};

    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id,display_name,username,avatar_url')
          .inFilter('id', userIds)
          .limit(250);
      final map = <String, Map<String, dynamic>>{};
      for (final r in (rows as List).whereType<Map<String, dynamic>>()) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        map[id] = r;
      }
      return map;
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  Future<_LeaderboardSnapshot?> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('stage_rankings_snapshots')
          .select('id,ranking_type,scope,scope_key,period_start,period_end,computed_at,entries,meta')
          .eq('ranking_type', _rankingType)
          .eq('scope', 'global')
          .order('period_end', ascending: false)
          .order('computed_at', ascending: false)
          .limit(1);

      final list = (rows as List).whereType<Map<String, dynamic>>().toList(growable: false);
      if (list.isEmpty) return null;

      final snap = list.first;
      final entriesRaw = snap['entries'];
      final entries = <_LeaderboardEntry>[];

      if (entriesRaw is List) {
        for (final e in entriesRaw) {
          if (e is Map) {
            final map = e.map((k, v) => MapEntry(k.toString(), v));
            entries.add(_LeaderboardEntry.fromMap(map));
          }
        }
      }

      // Enrich with profile info (best-effort).
      final ids = entries.map((e) => e.userId).where((s) => s.isNotEmpty).toSet().toList(growable: false);
      final profiles = await _bestEffortLoadProfiles(ids);
      final enriched = entries
          .map((e) => e.copyWith(profile: profiles[e.userId]))
          .toList(growable: false);

      DateTime? toDt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

      return _LeaderboardSnapshot(
        rankingType: (snap['ranking_type'] ?? '').toString(),
        periodStart: toDt(snap['period_start']),
        periodEnd: toDt(snap['period_end']),
        computedAt: toDt(snap['computed_at']),
        entries: enriched,
      );
    } catch (e) {
      if (_looksLikeNotConfigured(e)) return null;
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<_LeaderboardSnapshot?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load leaderboards. Please try again.',
            onRetry: _refresh,
          );
        }

        final data = snap.data;
        final entries = data?.entries ?? const <_LeaderboardEntry>[];

        String periodText(_LeaderboardSnapshot s) {
          final start = s.periodStart;
          final end = s.periodEnd;
          if (start == null || end == null) return 'Latest snapshot';
          final a = start.toLocal().toString().split(' ').first;
          final b = end.toLocal().toString().split(' ').first;
          return '$a → $b';
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_rankingType),
                      initialValue: _rankingType,
                      decoration: const InputDecoration(labelText: 'Ranking type'),
                      items: _rankingTypes.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(growable: false),
                      onChanged: (v) {
                        final next = (v ?? '').trim();
                        if (next.isEmpty || next == _rankingType) return;
                        setState(() {
                          _rankingType = next;
                          _future = _load();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (data == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No leaderboard snapshot available yet.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _rankingTypes[data.rankingType] ?? 'Leaderboard',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        periodText(data),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('No rankings yet'),
                )
              else
                ...entries.take(50).map((e) => _LeaderboardTile(entry: e)),
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
      appBar: AppBar(title: const Text('Leaderboards')),
      body: body,
    );
  }
}

class _LeaderboardSnapshot {
  const _LeaderboardSnapshot({
    required this.rankingType,
    required this.periodStart,
    required this.periodEnd,
    required this.computedAt,
    required this.entries,
  });

  final String rankingType;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? computedAt;
  final List<_LeaderboardEntry> entries;
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.userId,
    required this.rank,
    required this.score,
    required this.profile,
  });

  final String userId;
  final int rank;
  final num score;
  final Map<String, dynamic>? profile;

  String get displayName {
    final p = profile;
    if (p == null) return userId;
    final dn = (p['display_name'] ?? p['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final un = (p['username'] ?? '').toString().trim();
    if (un.isNotEmpty) return '@$un';
    return userId;
  }

  factory _LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '0').toString()) ?? 0;
    }

    num toNum(dynamic v) {
      if (v is num) return v;
      return num.tryParse((v ?? '0').toString()) ?? 0;
    }

    return _LeaderboardEntry(
      userId: (map['user_id'] ?? map['userId'] ?? '').toString(),
      rank: toInt(map['rank']),
      score: toNum(map['score']),
      profile: null,
    );
  }

  _LeaderboardEntry copyWith({Map<String, dynamic>? profile}) {
    return _LeaderboardEntry(
      userId: userId,
      rank: rank,
      score: score,
      profile: profile ?? this.profile,
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.entry});

  final _LeaderboardEntry entry;

  String _short(String s) {
    final t = s.trim();
    if (t.isEmpty) return '—';
    if (t.length <= 18) return t;
    return '${t.substring(0, 18)}…';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _short(entry.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            entry.score.toString(),
            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
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
