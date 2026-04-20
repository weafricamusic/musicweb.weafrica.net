import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../app/theme/weafrica_colors.dart';
import '../../app/widgets/glass_card.dart';
import '../live/screens/battle_detail_screen.dart';
import '../live/screens/vertical_battle_feed_screen.dart';
import '../live/services/battle_tickets_api.dart';
import '../live/services/live_discovery_service.dart';
import '../subscriptions/services/consumer_entitlement_gate.dart';
import 'event_detail_screen.dart';
import 'live_event.dart';
import 'live_events_repository.dart';
import 'services/events_tickets_api.dart';
import 'models/consumer_ticket.dart';

class EventsTabScreen extends StatefulWidget {
  const EventsTabScreen({super.key, this.showBattles = true});

  /// When false, the UI shows only events + tickets (no battles).
  final bool showBattles;

  @override
  State<EventsTabScreen> createState() => _EventsTabScreenState();
}

class _EventsTabScreenState extends State<EventsTabScreen> {
  late Future<_EventsTabData> _future;

  Future<void> _openTicketEventById(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event could not be loaded.')),
      );
      return;
    }

    final event = await LiveEventsRepository().getById(id);
    if (!mounted) return;
    if (event == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This event is no longer available.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(event: event),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EventsTabData> _load() async {
    final repo = LiveEventsRepository();

    var liveNowBattles = const <Map<String, dynamic>>[];
    var upcomingBattles = const <Map<String, dynamic>>[];
    if (widget.showBattles) {
      final discovery = LiveDiscoveryService();
      liveNowBattles = await discovery.listLiveNowBattles(limit: 30);
      upcomingBattles = await discovery.listUpcomingBattles(limit: 30);

      bool isBattleRow(Map<String, dynamic> row) {
        final channelId = (row['channel_id'] ?? row['channelId'] ?? '').toString().trim();
        final liveType = (row['live_type'] ?? '').toString().trim().toLowerCase();
        return channelId.startsWith('weafrica_battle_') || liveType == 'battle' || (row['battle_id'] ?? '').toString().trim().isNotEmpty;
      }

      liveNowBattles = liveNowBattles.where(isBattleRow).toList(growable: false);
      upcomingBattles = upcomingBattles.where(isBattleRow).toList(growable: false);
    }

    // Events table is public-read; keep country filter best-effort.
    final events = await repo.list(kind: '', limit: 80, countryCode: 'MW');
    final now = DateTime.now();

    final liveNowEvents = events
        .where((e) => (e.isLive == true || e.kind.trim().toLowerCase() == 'live') && (e.isOnline == true))
        .toList(growable: false);

    final upcomingEvents = events
        .where((e) {
          final starts = e.startsAt;
          if (starts == null) return false;
          if (e.isLive == true) return false;
          return starts.isAfter(now);
        })
        .toList(growable: false);

    return _EventsTabData(
      liveNowBattles: liveNowBattles,
      upcomingBattles: upcomingBattles,
      liveNowEvents: liveNowEvents,
      upcomingEvents: upcomingEvents,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  String _battleIdFromChannel(String channelId) {
    final c = channelId.trim();
    const prefix = 'weafrica_battle_';
    if (!c.startsWith(prefix)) return '';
    return c.substring(prefix.length).trim();
  }

  Future<List<Map<String, dynamic>>> _loadBattleTicketOptions(String battleId) async {
    final bid = battleId.trim();
    if (bid.isEmpty) return const [];

    try {
      final api = BattleTicketsApi();
      final rows = await api.listBattleTickets(battleId: bid);
      final out = <Map<String, dynamic>>[];

      for (final raw in rows) {
        final tier = (raw['tier'] ?? '').toString().trim().toLowerCase();
        if (tier.isEmpty) continue;

        final available = raw['is_available'];
        final isAvailable = available is bool ? available : available.toString().trim().toLowerCase() == 'true';
        if (!isAvailable) continue;

        final priceRaw = raw['price_amount'];
        final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(priceRaw.toString()) ?? 0;
        if (!price.isFinite || price <= 0) continue;

        final currency = (raw['price_currency'] ?? 'MWK').toString().trim().toUpperCase();
        if (currency.isEmpty) continue;

        final remainingRaw = raw['remaining'];
        final remaining = (remainingRaw is num) ? remainingRaw.toInt() : int.tryParse(remainingRaw.toString()) ?? 0;
        if (remaining <= 0) continue;

        out.add(<String, dynamic>{
          'tier': tier,
          'price': price,
          'currency': currency,
          'remaining': remaining,
        });
      }

      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _ensureBattleTicketAllowed(String channelId) async {
    final battleId = _battleIdFromChannel(channelId);
    if (battleId.isEmpty) return true;

    final options = await _loadBattleTicketOptions(battleId);
    if (!mounted) return false;
    if (options.isEmpty) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to buy a battle ticket.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return false;
    }

    // If paid tickets exist, require ownership before joining.
    final owned = await BattleTicketsApi().hasBattleTicket(battleId: battleId);
    if (!mounted) return false;
    if (owned) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Buy a battle ticket to join.'),
        backgroundColor: WeAfricaColors.error,
      ),
    );
    return false;
  }

  Future<bool> _ensureLiveAccessAllowed(Map<String, dynamic> row) async {
    final tier = (row['access_tier'] ?? '').toString().trim().toLowerCase();
    if (tier.isEmpty || tier == 'standard' || tier == 'watch_only') {
      return true;
    }

    if (tier == 'priority') {
      return ConsumerEntitlementGate.instance.ensureAllowed(
        context,
        capability: ConsumerCapability.priorityLiveAccess,
      );
    }

    return true;
  }

  Future<void> _watchBattle(Map<String, dynamic> row) async {
    final allowed = await _ensureLiveAccessAllowed(row);
    if (!allowed) return;

    final channelId =
        (row['channel_id'] ?? row['channelId'] ?? '').toString().trim();
    final battleId = (row['battle_id'] ?? row['battleId'] ?? '').toString().trim();
    if (channelId.isEmpty) return;

    final ticketOk = battleId.isEmpty ? true : await _ensureBattleTicketAllowed('weafrica_battle_$battleId');
    if (!ticketOk) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerticalBattleFeedScreen(
          initialChannelId: channelId,
        ),
      ),
    );
  }

  Future<void> _openBattleDetail(Map<String, dynamic> row, {required BattleDetailMode mode}) async {
    if (mode == BattleDetailMode.live) {
      final initialChannelId =
          (row['channel_id'] ?? row['channelId'] ?? '').toString().trim();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VerticalBattleFeedScreen(
            initialChannelId: initialChannelId.isEmpty ? null : initialChannelId,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BattleDetailScreen(
          row: row,
          mode: mode,
          onPrimaryAction: (mode == BattleDetailMode.live) ? () => _watchBattle(row) : null,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              isScrollable: false,
              indicatorColor: AppColors.stageGold,
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.textMuted,
              tabs: const [
                Tab(text: 'Live Now'),
                Tab(text: 'Upcoming'),
                Tab(text: 'My Tickets'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                FutureBuilder<_EventsTabData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snap.data;
                    if (data == null) {
                      return _emptyState('Could not load events', 'Pull to refresh and try again.');
                    }

                    final hasAny = (widget.showBattles && data.liveNowBattles.isNotEmpty) || data.liveNowEvents.isNotEmpty;
                    if (!hasAny) {
                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          children: [
                            const SizedBox(height: 120),
                            _emptyState(
                              'No live events',
                              widget.showBattles
                                  ? 'Check back later for live battles and online events.'
                                  : 'Check back later for online events.',
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (widget.showBattles && data.liveNowBattles.isNotEmpty) ...[
                            _sectionTitle('Live Battles'),
                            for (final row in data.liveNowBattles)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: _BattleCard(
                                  row: row,
                                  onTap: () => _openBattleDetail(row, mode: BattleDetailMode.live),
                                ),
                              ),
                          ],
                          if (data.liveNowEvents.isNotEmpty) _sectionTitle('Live Events'),
                          for (final e in data.liveNowEvents)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: _EventCard(
                                event: e,
                                badgeText: 'LIVE',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EventDetailScreen(event: e),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    );
                  },
                ),
                FutureBuilder<_EventsTabData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snap.data;
                    if (data == null) {
                      return _emptyState('Could not load events', 'Pull to refresh and try again.');
                    }

                    final hasAny = (widget.showBattles && data.upcomingBattles.isNotEmpty) || data.upcomingEvents.isNotEmpty;
                    if (!hasAny) {
                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          children: [
                            const SizedBox(height: 120),
                            _emptyState('No upcoming events', 'Create reminders and check back later.'),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (widget.showBattles && data.upcomingBattles.isNotEmpty) ...[
                            _sectionTitle('Upcoming Battles'),
                            for (final row in data.upcomingBattles)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: _BattleCard(
                                  row: row,
                                  onTap: () => _openBattleDetail(row, mode: BattleDetailMode.upcoming),
                                ),
                              ),
                          ],
                          if (data.upcomingEvents.isNotEmpty) _sectionTitle('Upcoming Events'),
                          for (final e in data.upcomingEvents)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: _EventCard(
                                event: e,
                                badgeText: 'UPCOMING',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EventDetailScreen(event: e),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    );
                  },
                ),
                _MyTicketsTab(onOpenEvent: (eventId) {
                  unawaited(_openTicketEventById(eventId));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventsTabData {
  const _EventsTabData({
    required this.liveNowBattles,
    required this.upcomingBattles,
    required this.liveNowEvents,
    required this.upcomingEvents,
  });

  final List<Map<String, dynamic>> liveNowBattles;
  final List<Map<String, dynamic>> upcomingBattles;
  final List<LiveEvent> liveNowEvents;
  final List<LiveEvent> upcomingEvents;
}

class _BattleCard extends StatelessWidget {
  const _BattleCard({
    required this.row,
    required this.onTap,
  });

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (row['title'] ?? '').toString().trim();
    final category = (row['category'] ?? '').toString().trim();
    final thumb = (row['thumbnail_url'] ?? '').toString().trim();

    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              color: AppColors.surface2,
              child: thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.live_tv, color: AppColors.textMuted),
                    )
                  : const Icon(Icons.live_tv, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35)),
                      ),
                      child: const Text('LIVE BATTLE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title.isNotEmpty ? title : 'Battle',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onTap,
    required this.badgeText,
  });

  final LiveEvent event;
  final VoidCallback onTap;
  final String badgeText;

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cover = event.coverImageUrl?.trim() ?? '';
    final subtitle = event.subtitle?.trim() ?? '';
    final startsAt = event.startsAt;

    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              color: AppColors.surface2,
              child: cover.isNotEmpty
                  ? Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.event, color: AppColors.textMuted),
                    )
                  : const Icon(Icons.event, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.stageGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.stageGold.withValues(alpha: 0.25)),
                      ),
                      child: Text(badgeText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted)),
                ],
                if (startsAt != null) ...[
                  const SizedBox(height: 4),
                  Text(_fmt(startsAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _MyTicketsTab extends StatefulWidget {
  const _MyTicketsTab({required this.onOpenEvent});

  final void Function(String eventId) onOpenEvent;

  @override
  State<_MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<_MyTicketsTab> {
  late Future<List<ConsumerTicket>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ConsumerTicket>> _load() async {
    try {
      return await const EventsTicketsApi().listMyTickets(limit: 80);
    } catch (_) {
      return const <ConsumerTicket>[];
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ConsumerTicket>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final tickets = snap.data ?? const <ConsumerTicket>[];
        if (tickets.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                const SizedBox(height: 120),
                _emptyState('No tickets yet', 'Your purchased tickets will show here with a QR code.'),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: tickets.length,
            itemBuilder: (context, i) {
              final t = tickets[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: GlassCard(
                  onTap: () {
                    final eid = t.eventId?.trim() ?? '';
                    if (eid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open this ticket.')), 
                      );
                      return;
                    }
                    widget.onOpenEvent(eid);
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: AppColors.surface2,
                          child: Center(
                            child: QrImageView(
                              data: t.qrCode,
                              size: 64,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.eventTitle?.trim().isNotEmpty == true ? t.eventTitle!.trim() : 'Event Ticket',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (t.ticketTypeName?.trim().isNotEmpty == true) ? t.ticketTypeName!.trim() : t.status,
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
