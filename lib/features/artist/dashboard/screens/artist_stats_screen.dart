import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/utils/result.dart';
import '../../../../app/widgets/empty_state.dart';
import '../../../../app/widgets/error_state.dart';
import '../../../../app/widgets/glass_card.dart';
import '../../../../app/widgets/shimmer_loading.dart';
import '../../../../app/theme.dart';
import '../services/artist_identity_service.dart';

class ArtistStatsScreen extends StatefulWidget {
  const ArtistStatsScreen({super.key});

  @override
  State<ArtistStatsScreen> createState() => _ArtistStatsScreenState();
}

class _ArtistStatsScreenState extends State<ArtistStatsScreen> {
  final _identity = ArtistIdentityService();

  int _days = 7;
  late Future<Result<_StatsData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Result<_StatsData>> _load() async {
    try {
      final artistId = await _identity.resolveArtistIdForCurrentUser();
      if (artistId == null) {
        return const Success(_StatsData(playSeries: <_DayPoint>[], topSongs: <Map<String, dynamic>>[]));
      }

      final client = Supabase.instance.client;
      final since = DateTime.now().toUtc().subtract(Duration(days: _days));

      final playSeries = await _bestEffortPlaysPerDay(client: client, artistId: artistId, since: since);
      final topSongs = await _bestEffortTopSongs(client: client, artistId: artistId);

      return Success(_StatsData(playSeries: playSeries, topSongs: topSongs));
    } catch (e) {
      return Failure(Exception('Could not load analytics: $e'));
    }
  }

  Future<List<_DayPoint>> _bestEffortPlaysPerDay({
    required SupabaseClient client,
    required String artistId,
    required DateTime since,
  }) async {
    try {
      final rows = await client
          .from('plays')
          .select('created_at')
          .eq('artist_id', artistId)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: true)
          .limit(2000);

      final items = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
      return _groupByDay(items, key: 'created_at');
    } catch (_) {
      try {
        final rows = await client
            .from('play_events')
            .select('created_at')
            .eq('artist_id', artistId)
            .inFilter('content_type', const ['song', 'track'])
            .gte('created_at', since.toIso8601String())
            .order('created_at', ascending: true)
            .limit(2000);

        final items = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
        return _groupByDay(items, key: 'created_at');
      } catch (_) {
        return const <_DayPoint>[];
      }
    }
  }

  List<_DayPoint> _groupByDay(List<Map<String, dynamic>> rows, {required String key}) {
    final map = <DateTime, int>{};
    for (final r in rows) {
      final raw = r[key];
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw.toString());
      if (dt == null) continue;
      final day = DateTime.utc(dt.toUtc().year, dt.toUtc().month, dt.toUtc().day);
      map[day] = (map[day] ?? 0) + 1;
    }

    final days = map.keys.toList()..sort();
    return days.map((d) => _DayPoint(d, map[d] ?? 0)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _bestEffortTopSongs({
    required SupabaseClient client,
    required String artistId,
  }) async {
    try {
      final rows = await client
          .from('songs')
          .select('id,title,plays_count,plays,likes,likes_count,comments,comments_count,created_at')
          .eq('artist_id', artistId)
          .order('plays_count', ascending: false)
          .limit(50);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (_) {
      try {
        final rows = await client
            .from('songs')
            .select('id,title,plays_count,plays,likes,likes_count,comments,comments_count,created_at')
            .eq('artist_id', artistId)
            .order('created_at', ascending: false)
            .limit(50);
        return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics / Stats'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Date range',
            onSelected: (v) {
              setState(() {
                _days = v;
                _future = _load();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
              PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
            icon: const Icon(Icons.calendar_today),
          ),
        ],
      ),
      body: FutureBuilder<Result<_StatsData>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: ShimmerLoading(
                child: GlassCard(
                  width: double.infinity,
                  height: 220,
                  child: SizedBox.expand(),
                ),
              ),
            );
          }
          final result = snap.data;
          if (result == null || result.isFailure) {
            return ErrorState(
              message: result?.error?.toString() ?? 'Could not load analytics.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final data = result.data ?? const _StatsData(playSeries: <_DayPoint>[], topSongs: <Map<String, dynamic>>[]);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Plays per day (last $_days days)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _ChartCard(series: data.playSeries),
              const SizedBox(height: 18),
              Text(
                'Top performing songs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (data.topSongs.isEmpty)
                const EmptyState(message: 'No song analytics yet.', icon: Icons.music_note)
              else
                ...data.topSongs.take(20).map((s) {
                  final title = (s['title'] ?? 'Untitled').toString();
                  final plays = (s['plays_count'] ?? s['plays'] ?? 0).toString();
                  final likes = (s['likes'] ?? s['likes_count'] ?? 0).toString();
                  final comments = (s['comments'] ?? s['comments_count'] ?? 0).toString();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text(
                            'Plays $plays • Likes $likes • Comments $comments',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

@immutable
class _StatsData {
  const _StatsData({required this.playSeries, required this.topSongs});

  final List<_DayPoint> playSeries;
  final List<Map<String, dynamic>> topSongs;
}

@immutable
class _DayPoint {
  const _DayPoint(this.day, this.value);

  final DateTime day;
  final int value;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.series});

  final List<_DayPoint> series;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      height: 180,
      padding: const EdgeInsets.all(14),
      child: series.isEmpty
          ? Center(
              child: Text(
                'No play events data yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            )
          : CustomPaint(
              painter: _LineChartPainter(series: series),
              child: const SizedBox.expand(),
            ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.series});

  final List<_DayPoint> series;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = 10.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final maxV = series.map((p) => p.value).fold<int>(0, math.max);
    final maxY = math.max(1, maxV).toDouble();

    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    canvas.drawLine(Offset(pad, pad), Offset(pad, pad + h), axisPaint);
    canvas.drawLine(Offset(pad, pad + h), Offset(pad + w, pad + h), axisPaint);

    final linePaint = Paint()
      ..color = AppColors.brandPurple
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = AppColors.brandPurple;

    final n = series.length;
    final dx = n <= 1 ? 0.0 : (w / (n - 1));

    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = series[i].value.toDouble();
      final x = pad + dx * i;
      final y = pad + h - (v / maxY) * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.series != series;
  }
}
