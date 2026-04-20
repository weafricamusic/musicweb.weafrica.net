import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjHighlightsScreen extends StatefulWidget {
  const DjHighlightsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjHighlightsScreen> createState() => _DjHighlightsScreenState();
}

class _DjHighlightsScreenState extends State<DjHighlightsScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late final String _djUid;
  late Future<_HighlightsData> _future;

  @override
  void initState() {
    super.initState();
    _djUid = _identity.requireDjUid();
    _future = _load();
  }

  Future<_HighlightsData> _load() async {
    final setsFuture = _service.listSets(djUid: _djUid, limit: 500).catchError((_) => const <DjSet>[]);
    final pastLivesFuture = _service.listPastLiveSessions(djUid: _djUid, limit: 200).catchError((_) => const <DjEvent>[]);

    final res = await Future.wait<dynamic>([setsFuture, pastLivesFuture]);
    return _HighlightsData(
      sets: res[0] as List<DjSet>,
      pastLives: res[1] as List<DjEvent>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<_HighlightsData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load highlights. Please try again.',
            onRetry: _refresh,
          );
        }

        final data = snap.data ?? const _HighlightsData(sets: <DjSet>[], pastLives: <DjEvent>[]);

        final topByPlays = List<DjSet>.from(data.sets)
          ..sort((a, b) => b.plays.compareTo(a.plays));
        final topByCoins = List<DjSet>.from(data.sets)
          ..sort((a, b) => b.coinsEarned.compareTo(a.coinsEarned));

        final livesWithReplay = data.pastLives
            .where((e) => (e.replayUrl ?? '').trim().isNotEmpty)
            .toList(growable: false);

        int metaInt(DjEvent e, String key) {
          final v = e.metadata[key];
          if (v is int) return v;
          if (v is num) return v.toInt();
          return int.tryParse((v ?? '0').toString()) ?? 0;
        }

        Widget sectionTitle(String title) {
          return Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          );
        }

        Widget emptyCard(String text) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionTitle('TOP SETS (PLAYS)'),
                const SizedBox(height: 10),
                if (topByPlays.isEmpty)
                  emptyCard('No sets yet.')
                else
                  ...topByPlays.take(5).map(
                    (s) => _SetHighlightTile(set: s, subtitle: '${s.plays} plays'),
                  ),

                const SizedBox(height: 16),
                sectionTitle('TOP SETS (COINS)'),
                const SizedBox(height: 10),
                if (topByCoins.isEmpty)
                  emptyCard('No sets yet.')
                else
                  ...topByCoins.take(5).map(
                    (s) => _SetHighlightTile(
                      set: s,
                      subtitle: '${s.coinsEarned} coins earned',
                    ),
                  ),

                const SizedBox(height: 16),
                sectionTitle('LIVE REPLAYS'),
                const SizedBox(height: 10),
                if (livesWithReplay.isEmpty)
                  emptyCard('No replays found yet.')
                else
                  ...livesWithReplay.take(10).map((e) {
                    final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
                    final viewers = metaInt(e, 'viewers');
                    final coins = metaInt(e, 'coins_earned');
                    final parts = <String>[];
                    if (viewers > 0) parts.add('$viewers viewers');
                    if (coins > 0) parts.add('$coins coins');
                    final subtitle = parts.isEmpty ? 'Replay available' : parts.join(' • ');

                    return _ReplayTile(
                      title: title,
                      subtitle: subtitle,
                      url: e.replayUrl!,
                      onOpen: () => _openUrl(e.replayUrl!),
                    );
                  }),
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
        title: const Text('Highlights'),
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

class _HighlightsData {
  const _HighlightsData({required this.sets, required this.pastLives});

  final List<DjSet> sets;
  final List<DjEvent> pastLives;
}

class _SetHighlightTile extends StatelessWidget {
  const _SetHighlightTile({required this.set, required this.subtitle});

  final DjSet set;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final genre = (set.genre ?? '').trim();
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
          Text(set.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (genre.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Genre: $genre', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _ReplayTile extends StatelessWidget {
  const _ReplayTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final String url;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onOpen,
            child: const Text('Open'),
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
