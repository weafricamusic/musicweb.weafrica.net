import 'package:flutter/material.dart';

import '../../../app/constants/weafrica_power_voice.dart';
import '../../../app/theme.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjStatsScreen extends StatefulWidget {
  const DjStatsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjStatsScreen> createState() => _DjStatsScreenState();
}

class _DjStatsScreenState extends State<DjStatsScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<DjStatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DjStatsData> _load() async {
    final uid = _identity.requireDjUid();

    final setsFuture = _service.listSets(djUid: uid, limit: 1000);
    final earningsFuture = _service.bestEffortTotalEarnings(djUid: uid);

    final results = await Future.wait([setsFuture, earningsFuture]);
    final sets = results[0] as List<DjSet>;
    final earnings = results[1] as num;

    // Aggregate stats
    var totalPlays = 0;
    var totalLikes = 0;
    var totalComments = 0;
    var totalCoins = 0;
    final playData = <DateTime, int>{};

    for (final set in sets) {
      totalPlays += set.plays;
      totalLikes += set.likes;
      totalComments += set.comments;
      totalCoins += set.coinsEarned;

      // For chart: group by date
      final date = set.createdAt;
      final day = DateTime(date.year, date.month, date.day);
      playData[day] = (playData[day] ?? 0) + set.plays;
    }

    final sortedSets = List<DjSet>.from(sets)
      ..sort((a, b) => b.plays.compareTo(a.plays));
    final topSets = sortedSets.take(5).toList(growable: false);

    // Sort play data by date
    final sortedPlayData = playData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return DjStatsData(
      totalPlays: totalPlays,
      totalLikes: totalLikes,
      totalComments: totalComments,
      totalCoinsEarned: totalCoins,
      totalEarnings: earnings,
      setsCount: sets.length,
      playChartData: sortedPlayData,
      topSets: topSets,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<DjStatsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Could not load stats. Please try again.',
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return _ErrorState(
            message: WeAfricaPowerVoice.noDataSignal,
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _StatCard('Total Plays', data.totalPlays.toString())),
                const SizedBox(width: 12),
                Expanded(child: _StatCard('Total Likes', data.totalLikes.toString())),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard('Comments', data.totalComments.toString())),
                const SizedBox(width: 12),
                Expanded(child: _StatCard('Coins Earned', data.totalCoinsEarned.toString())),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard('Total Earnings', '\$${data.totalEarnings.toStringAsFixed(2)}'),

            const SizedBox(height: 24),
            const Text(
              'Play Trends',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _PlayChart(data: data.playChartData),

            const SizedBox(height: 24),
            const Text(
              'Top Sets',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (data.topSets.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text('No sets yet'),
              )
            else
              ...data.topSets.map(
                (s) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              (s.genre ?? '').trim().isEmpty ? 'Genre: —' : 'Genre: ${s.genre}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${s.plays} plays', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('DJ Analytics')),
      body: body,
    );
  }
}

class DjStatsData {
  final int totalPlays;
  final int totalLikes;
  final int totalComments;
  final int totalCoinsEarned;
  final num totalEarnings;
  final int setsCount;
  final List<MapEntry<DateTime, int>> playChartData;
  final List<DjSet> topSets;

  const DjStatsData({
    required this.totalPlays,
    required this.totalLikes,
    required this.totalComments,
    required this.totalCoinsEarned,
    required this.totalEarnings,
    required this.setsCount,
    required this.playChartData,
    required this.topSets,
  });
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PlayChart extends StatelessWidget {
  const _PlayChart({required this.data});

  final List<MapEntry<DateTime, int>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text('No play data yet'),
      );
    }

    // Simple bar chart placeholder
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((entry) {
                final maxPlays = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
                final height = maxPlays == 0 ? 0.0 : (entry.value / maxPlays) * 100;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: height,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: data.map((entry) {
              return Text(
                '${entry.key.month}/${entry.key.day}',
                style: const TextStyle(fontSize: 10),
              );
            }).toList(),
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