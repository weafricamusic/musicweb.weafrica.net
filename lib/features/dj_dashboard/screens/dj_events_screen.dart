import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../core/widgets/studio_card.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjEventsScreen extends StatefulWidget {
  const DjEventsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjEventsScreen> createState() => _DjEventsScreenState();
}

class _DjEventsScreenState extends State<DjEventsScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<_DjEventsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DjEventsData> _load() async {
    final uid = _identity.requireDjUid();

    final upcomingFuture = _service
        .listUpcomingLiveSchedule(djUid: uid, limit: 50)
        .catchError((_) => const <DjEvent>[]);
    final pastFuture = _service
        .listPastLiveSessions(djUid: uid, limit: 50)
        .catchError((_) => const <DjEvent>[]);

    final results = await Future.wait<dynamic>([upcomingFuture, pastFuture]);

    return _DjEventsData(
      djUid: uid,
      upcoming: results[0] as List<DjEvent>,
      past: results[1] as List<DjEvent>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<DateTime?> _pickDateTime(
    BuildContext context, {
    required DateTime initial,
  }) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!context.mounted || date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!context.mounted || time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _fmtDateTime(BuildContext context, DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final loc = MaterialLocalizations.of(context);
    final date = loc.formatShortDate(local);
    final time = loc.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date $time';
  }

  Future<void> _scheduleLive(String djUid) async {
    final now = DateTime.now();
    final startInitial = now.add(const Duration(hours: 1));

    final startsAt = await _pickDateTime(context, initial: startInitial);
    if (!mounted || startsAt == null) return;

    final endsAt = await _pickDateTime(context, initial: startsAt.add(const Duration(hours: 1)));
    if (!mounted || endsAt == null) return;

    if (!endsAt.isAfter(startsAt)) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
      return;
    }

    try {
      await _service.scheduleLive(
        djUid: djUid,
        startsAt: startsAt.toUtc(),
        endsAt: endsAt.toUtc(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Live session scheduled.')));

      await _refresh();
    } catch (e, st) {
      UserFacingError.log('DjEventsScreen._scheduleLive', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Could not schedule. Please try again.',
              ),
            ),
          ),
        );
    }
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _eventCard(BuildContext context, DjEvent e) {
    final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
    final when = '${_fmtDateTime(context, e.startsAt)} → ${_fmtDateTime(context, e.endsAt)}';
    final status = (e.status).trim();
    final subtitle = status.isEmpty ? when : '$when • ${status.toUpperCase()}';

    final type = e.eventType.trim().isEmpty ? 'live' : e.eventType.trim();
    final tag = type.toUpperCase();

    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              type.toLowerCase().contains('live') ? Icons.videocam_outlined : Icons.event_outlined,
              color: AppColors.textMuted,
            ),
          ),
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
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
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
              tag,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.stageGold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: showAppBar
          ? AppBar(
              title: const Text('Events & Live'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: FutureBuilder<_DjEventsData>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                StudioCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule your live sessions',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Plan upcoming gigs and lives for your fans.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: data == null ? null : () => _scheduleLive(data.djUid),
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Create'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _sectionTitle('UPCOMING'),
                const SizedBox(height: 10),
                if (loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (data == null)
                  const StudioCard(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not load events.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else if (data.upcoming.isEmpty)
                  const StudioCard(
                    padding: EdgeInsets.all(16),
                    child: Text('No upcoming events.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  ...data.upcoming.take(10).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _eventCard(context, e),
                      )),
                const SizedBox(height: 16),

                _sectionTitle('PAST'),
                const SizedBox(height: 10),
                if (!loading && data != null && data.past.isEmpty)
                  const StudioCard(
                    padding: EdgeInsets.all(16),
                    child: Text('No past events yet.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else if (data != null)
                  ...data.past.take(10).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _eventCard(context, e),
                      )),

                if (snap.hasError) ...[
                  const SizedBox(height: 14),
                  Text(
                    UserFacingError.message(
                      snap.error,
                      fallback: 'Could not load events. Please try again.',
                    ),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DjEventsData {
  const _DjEventsData({
    required this.djUid,
    required this.upcoming,
    required this.past,
  });

  final String djUid;
  final List<DjEvent> upcoming;
  final List<DjEvent> past;
}
