import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../core/widgets/studio_card.dart';
import '../../auth/user_role.dart';
import '../../live/screens/go_live_setup_screen.dart';
import '../../live_events/live_event.dart';
import 'artist_live_battles_screen.dart';

class ArtistEventsLiveScreen extends StatefulWidget {
  const ArtistEventsLiveScreen({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<ArtistEventsLiveScreen> createState() => _ArtistEventsLiveScreenState();
}

class _ArtistEventsLiveScreenState extends State<ArtistEventsLiveScreen> {
  late Future<List<LiveEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String _hostName() {
    final u = FirebaseAuth.instance.currentUser;
    final display = (u?.displayName ?? '').trim();
    if (display.isNotEmpty) return display;
    final email = (u?.email ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Artist';
  }

  Future<List<LiveEvent>> _load() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return const <LiveEvent>[];

    final client = Supabase.instance.client;

    try {
      final rows = await client
          .from('events')
          .select('*')
          .eq('host_user_id', uid)
          .order('created_at', ascending: false)
          .limit(80);

      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(LiveEvent.fromSupabase)
          .toList(growable: false);
    } catch (_) {
      // Schema drift fallback: some deployments use user_id.
      try {
        final rows = await client
            .from('events')
            .select('*')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(80);

        return (rows as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(LiveEvent.fromSupabase)
            .toList(growable: false);
      } catch (_) {
        return const <LiveEvent>[];
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
    if (dt == null) return 'Pick…';
    final local = dt.toLocal();
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(local)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Future<void> _createEventDialog({required bool ticketed}) async {
    final rootContext = context;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final totalCtrl = TextEditingController();

    var kind = 'event';
    DateTime? startsAt;
    DateTime? endsAt;

    try {
      final ok = await showDialog<bool>(
        context: rootContext,
        builder: (ctx) {
          var saving = false;

          return StatefulBuilder(
            builder: (ctx, setState) {
              Future<void> save() async {
                if (saving) return;

                final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
                if (uid.isEmpty) return;

                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Title is required.')),
                  );
                  return;
                }

                if (startsAt == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Start time is required.')),
                  );
                  return;
                }

                num? ticketPrice;
                int? totalTickets;

                if (ticketed) {
                  ticketPrice = num.tryParse(priceCtrl.text.trim());
                  totalTickets = int.tryParse(totalCtrl.text.trim());
                }

                setState(() => saving = true);
                try {
                  await _createEvent(
                    uid: uid,
                    hostName: _hostName(),
                    title: title,
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    kind: kind,
                    startsAt: startsAt!,
                    endsAt: endsAt,
                    ticketPrice: ticketPrice,
                    totalTickets: totalTickets,
                  );

                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e, st) {
                  UserFacingError.log('ArtistEventsLiveScreen.createEvent', e, st);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx)
                    ..removeCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          UserFacingError.message(
                            e,
                            fallback: 'Could not create event. Please try again.',
                          ),
                        ),
                      ),
                    );
                  setState(() => saving = false);
                }
              }

              return AlertDialog(
                title: Text(ticketed ? 'Create ticketed event' : 'Create event'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(labelText: 'Description (optional)'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'event', label: Text('Event')),
                            ButtonSegment(value: 'live', label: Text('Live')),
                          ],
                          selected: {kind},
                          onSelectionChanged: (s) => setState(() => kind = s.first),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final picked = await _pickDateTime(
                                          ctx,
                                          initial: DateTime.now().add(const Duration(hours: 1)),
                                        );
                                        if (!ctx.mounted) return;
                                        if (picked == null) return;
                                        setState(() => startsAt = picked);
                                      },
                                icon: const Icon(Icons.event_available_outlined),
                                label: Text('Start: ${_fmtDateTime(ctx, startsAt)}'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: saving || startsAt == null
                                    ? null
                                    : () async {
                                        final picked = await _pickDateTime(
                                          ctx,
                                          initial: startsAt!.add(const Duration(hours: 1)),
                                        );
                                        if (!ctx.mounted) return;
                                        if (picked == null) return;
                                        setState(() => endsAt = picked);
                                      },
                                icon: const Icon(Icons.event_busy_outlined),
                                label: Text('End: ${_fmtDateTime(ctx, endsAt)}'),
                              ),
                            ),
                          ],
                        ),
                        if (ticketed) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: priceCtrl,
                            decoration: const InputDecoration(labelText: 'Ticket price (optional)'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: totalCtrl,
                            decoration: const InputDecoration(labelText: 'Total tickets (optional)'),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!rootContext.mounted) return;

      if (ok == true) {
        ScaffoldMessenger.of(rootContext)
          ..removeCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Event created.')));
        await _refresh();
      }
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
      priceCtrl.dispose();
      totalCtrl.dispose();
    }
  }

  Future<void> _createEvent({
    required String uid,
    required String hostName,
    required String title,
    required String kind,
    required DateTime startsAt,
    DateTime? endsAt,
    String? description,
    num? ticketPrice,
    int? totalTickets,
  }) async {
    final client = Supabase.instance.client;

    final now = DateTime.now().toUtc().toIso8601String();
    final startsIso = startsAt.toUtc().toIso8601String();
    final endsIso = endsAt?.toUtc().toIso8601String();
    final uidIsUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(uid);

    final meta = <String, dynamic>{};
    if (ticketPrice != null) meta['ticket_price'] = ticketPrice;
    if (totalTickets != null) meta['total_tickets'] = totalTickets;
    if (meta.isNotEmpty) meta['tickets_sold'] = 0;

    final base = <String, dynamic>{
      'title': title,
      'subtitle': description,
      'description': description,
      'kind': kind,
      'is_live': kind == 'live',
      'host_name': hostName,
      'poster_url': '',
      'country_code': 'MW',
      'is_online': true,
      'lineup': <String>[hostName],
      if (meta.isNotEmpty) 'metadata': meta,
      ...?(ticketPrice == null ? null : {'ticket_price': ticketPrice}),
      ...?(totalTickets == null ? null : {'total_tickets': totalTickets}),
      if (meta.isNotEmpty) 'tickets_sold': 0,
      'created_at': now,
      'updated_at': now,
    };

    final timeBoth = <String, dynamic>{
      'starts_at': startsIso,
      'date_time': startsIso,
      'ends_at': ?endsIso,
    };
    final timeStartsAt = <String, dynamic>{
      'starts_at': startsIso,
      'ends_at': ?endsIso,
    };
    final timeDateTime = <String, dynamic>{
      'date_time': startsIso,
      'ends_at': ?endsIso,
    };

    final candidates = <Map<String, dynamic>>[
      {
        ...base,
        ...timeBoth,
        'artist_id': uid,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeStartsAt,
        'artist_id': uid,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeDateTime,
        'artist_id': uid,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeBoth,
        'artist_id': uid,
      },
      {
        ...base,
        ...timeStartsAt,
        'artist_id': uid,
      },
      {
        ...base,
        ...timeDateTime,
        'artist_id': uid,
      },
      {
        ...base,
        ...timeBoth,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeStartsAt,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeDateTime,
        'firebase_user_id': uid,
      },
      {
        ...base,
        ...timeBoth,
      },
      {
        ...base,
        ...timeStartsAt,
      },
      if (uidIsUuid)
        {
          ...base,
          ...timeStartsAt,
          'host_user_id': uid,
        },
      if (uidIsUuid)
        {
          ...base,
          ...timeStartsAt,
          'user_id': uid,
        },
    ];

    Object? lastError;

    Future<bool> insertWithCompat(Map<String, dynamic> row) async {
      final working = Map<String, dynamic>.from(row);

      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          await client.from('events').insert(working);
          return true;
        } catch (e) {
          lastError = e;

          if (e is PostgrestException) {
            final msg = e.message.toLowerCase();
            final details = (e.details ?? '').toString().toLowerCase();

            // PGRST204: "Could not find the 'metadata' column of 'events' in the schema cache"
            // Strip missing columns and retry.
            final missingCol = RegExp(
              r"could not find the '([a-z0-9_]+)' column",
              caseSensitive: false,
            ).firstMatch(e.message)?.group(1);
            if (missingCol != null && working.containsKey(missingCol)) {
              working.remove(missingCol);
              continue;
            }

            // Some deployments don't have ticketing/metadata columns.
            if (msg.contains('schema cache') || msg.contains('does not exist') || details.contains('schema cache')) {
              var removedAny = false;
              for (final k in const [
                'metadata',
                'ticket_price',
                'total_tickets',
                'tickets_sold',
                'subtitle',
                'ends_at',
              ]) {
                if (working.containsKey(k)) {
                  working.remove(k);
                  removedAny = true;
                }
              }
              if (removedAny) continue;
            }

            // Some deployments use UUID for certain user id columns.
            // If we accidentally hit one, try the next candidate shape.
            if (msg.contains('invalid input syntax for type uuid') ||
                details.contains('invalid input syntax for type uuid')) {
              return false;
            }

            // Mixed schemas can have different NOT NULL requirements.
            // Treat these as recoverable so we can try the next candidate.
            if (msg.contains('not-null') || details.contains('not-null')) {
              return false;
            }

            final schemaMismatch = msg.contains('column') ||
                msg.contains('schema cache') ||
                msg.contains('does not exist') ||
                details.contains('schema cache') ||
                details.contains('column');

            if (msg.contains('permission denied') || msg.contains('row level security')) {
              return false;
            }

            if (schemaMismatch) {
              return false;
            }
          }

          return false;
        }
      }

      return false;
    }

    for (final row in candidates) {
      final ok = await insertWithCompat(row);
      if (ok) return;
    }

    throw lastError ?? StateError('Create event failed.');
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
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
            child: Icon(icon, color: AppColors.stageGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _eventCard(LiveEvent e) {
    final kind = e.kind.trim().isEmpty ? 'event' : e.kind.trim();
    final when = e.startsAt == null ? 'TBA' : e.startsAt!.toLocal().toString().split('.').first;
    final subtitle = (e.subtitle ?? '').trim();

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
              kind.toLowerCase() == 'live' || e.isLive == true ? Icons.videocam_outlined : Icons.event_outlined,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  subtitle.isEmpty ? when : '$when • $subtitle',
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
              kind.toUpperCase(),
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
      body: FutureBuilder<List<LiveEvent>>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;
          final events = snap.data ?? const <LiveEvent>[];

          final now = DateTime.now();
          final upcoming = events.where((e) => e.startsAt == null || e.startsAt!.isAfter(now.subtract(const Duration(minutes: 5)))).toList(growable: false);
          final past = events.where((e) => e.startsAt != null && e.startsAt!.isBefore(now.subtract(const Duration(minutes: 5)))).toList(growable: false);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // TOP CARD REMOVED - No more + CREATE button duplication
                const SizedBox(height: 4),

                // MY BATTLES Card (renamed from "Battles")
                _actionCard(
                  icon: Icons.sports_mma_outlined,
                  title: 'My Battles',
                  subtitle: 'View invites and active battles.',
                  onTap: () => _open(context, const ArtistLiveBattlesScreen()),
                ),
                const SizedBox(height: 12),

                // GO LIVE Card (updated description)
                _actionCard(
                  icon: Icons.videocam_outlined,
                  title: 'Go Live',
                  subtitle: 'Start a solo live or battle.',
                  onTap: () {
                    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
                    if (uid.isEmpty) return;
                    _open(
                      context,
                      GoLiveSetupScreen(
                        role: UserRole.artist,
                        hostId: uid,
                        hostName: _hostName(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // CREATE EVENT Card
                _actionCard(
                  icon: Icons.event_outlined,
                  title: 'Create Event',
                  subtitle: 'Schedule an upcoming event.',
                  onTap: () => _createEventDialog(ticketed: false),
                ),
                const SizedBox(height: 12),

                // TICKET SALES Card (updated description)
                _actionCard(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Ticket Sales',
                  subtitle: 'Create ticketed events.',
                  onTap: () => _createEventDialog(ticketed: true),
                ),
                const SizedBox(height: 18),

                Text(
                  'UPCOMING',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 10),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                else if (upcoming.isEmpty)
                  const StudioCard(
                    padding: EdgeInsets.all(16),
                    child: Text('No upcoming events yet.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  ...upcoming.take(10).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _eventCard(e),
                      )),

                const SizedBox(height: 10),
                Text(
                  'PAST',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 10),
                if (!loading && past.isEmpty)
                  const StudioCard(
                    padding: EdgeInsets.all(16),
                    child: Text('No past events yet.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  ...past.take(10).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _eventCard(e),
                      )),

                if (snap.hasError) ...[
                  const SizedBox(height: 12),
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
          );
        },
      ),
    );
  }
}