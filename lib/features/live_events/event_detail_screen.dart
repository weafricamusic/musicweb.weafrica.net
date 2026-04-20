import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../app/theme/weafrica_colors.dart';
import '../../app/widgets/glass_card.dart';
import '../subscriptions/checkout_webview_screen.dart';
import 'live_event.dart';
import 'models/consumer_ticket.dart';
import 'models/event_ticket_type.dart';
import 'services/event_tickets_repository.dart';
import 'services/events_tickets_api.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.event});

  final LiveEvent event;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Future<_EventDetails> _detailsFuture;
  late Future<List<EventTicketType>> _ticketTypesFuture;
  late Future<List<ConsumerTicket>> _myTicketsFuture;

  String? _selectedTicketId;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
    _ticketTypesFuture = EventTicketsRepository().listByEventId(eventId: widget.event.id);
    _myTicketsFuture = const EventsTicketsApi().listMyTickets(eventId: widget.event.id, limit: 200);
  }

  Future<_EventDetails> _loadDetails() async {
    final id = widget.event.id.trim();
    if (id.isEmpty) {
      return _EventDetails.fromModel(widget.event, row: const <String, dynamic>{});
    }

    try {
      final sb = Supabase.instance.client;
      final Map<String, dynamic>? row = await sb.from('events').select('*').eq('id', id).maybeSingle();
      if (row == null) {
        return _EventDetails.fromModel(widget.event, row: const <String, dynamic>{});
      }
      final m = row.map((k, v) => MapEntry(k.toString(), v));
      return _EventDetails.fromModel(widget.event, row: m);
    } catch (e) {
      developer.log('EventDetailScreen _loadDetails failed', error: e);
      return _EventDetails.fromModel(widget.event, row: const <String, dynamic>{});
    }
  }

  Future<void> _refreshTickets() async {
    setState(() {
      _myTicketsFuture = const EventsTicketsApi().listMyTickets(eventId: widget.event.id, limit: 200);
      _ticketTypesFuture = EventTicketsRepository().listByEventId(eventId: widget.event.id);
    });
  }

  Future<void> _buyTicket({required _EventDetails details, required EventTicketType? selectedType}) async {
    if (_buying) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to buy a ticket.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    setState(() => _buying = true);
    try {
      final res = await const EventsTicketsApi().buyTicket(
        eventId: widget.event.id,
        ticketId: selectedType?.id,
        qty: 1,
      );

      if (!mounted) return;

      if (res.isPaid && res.checkoutUrl != null) {
        final checkoutUri = Uri.tryParse(res.checkoutUrl!);
        if (checkoutUri == null) {
          throw StateError('Invalid checkout URL');
        }

        final outcome = await Navigator.of(context).push<CheckoutOutcome>(
          MaterialPageRoute<CheckoutOutcome>(
            builder: (_) => CheckoutWebviewScreen(initialUrl: checkoutUri),
          ),
        );

        if (!mounted) return;
        if (outcome != CheckoutOutcome.completed) return;

        if (res.txRef.trim().isNotEmpty) {
          for (var i = 0; i < 4; i++) {
            try {
              final ok = await const EventsTicketsApi().verifyPayChanguPayment(txRef: res.txRef);
              if (ok) break;
            } catch (_) {
              // Ignore and retry briefly; webhook/manual verify races are expected.
            }
            await Future<void>.delayed(const Duration(milliseconds: 900));
          }
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment processing. Refreshing tickets...')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket issued.')),
        );
      }

      await _refreshTickets();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.title),
      ),
      body: FutureBuilder<_EventDetails>(
        future: _detailsFuture,
        builder: (context, detailsSnap) {
          if (detailsSnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final details = detailsSnap.data ?? _EventDetails.fromModel(widget.event, row: const <String, dynamic>{});

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _detailsFuture = _loadDetails();
              });
              await _refreshTickets();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _HeroCard(details: details),
                const SizedBox(height: 14),
                if (details.description.isNotEmpty)
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Text(details.description, style: const TextStyle(color: AppColors.textMuted, height: 1.35)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                FutureBuilder<List<EventTicketType>>(
                  future: _ticketTypesFuture,
                  builder: (context, ticketSnap) {
                    final types = ticketSnap.data ?? const <EventTicketType>[];

                    if (types.isNotEmpty && _selectedTicketId == null) {
                      _selectedTicketId = types.first.id;
                    }

                    return GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tickets', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          if (types.isEmpty)
                            const Text('No ticket tiers published yet.', style: TextStyle(color: AppColors.textMuted))
                          else
                            ...types.map((t) {
                              final selected = _selectedTicketId == t.id;
                              final priceLabel = t.isFree ? 'FREE' : '${t.currency} ${t.priceMwk.toStringAsFixed(0)}';
                              final soldOut = t.quantityTotal > 0 && t.remaining <= 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: InkWell(
                                  onTap: soldOut
                                      ? null
                                      : () {
                                          setState(() => _selectedTicketId = t.id);
                                        },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface2.withValues(alpha: selected ? 0.55 : 0.35),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: (selected ? AppColors.stageGold : AppColors.border).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                                              const SizedBox(height: 4),
                                              Text(
                                                soldOut
                                                    ? 'Sold out'
                                                    : (t.quantityTotal > 0 ? '${t.remaining} left' : 'Available'),
                                                style: const TextStyle(color: AppColors.textMuted),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.stageGold.withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: AppColors.stageGold.withValues(alpha: 0.25)),
                                          ),
                                          child: Text(priceLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                FutureBuilder<List<ConsumerTicket>>(
                  future: _myTicketsFuture,
                  builder: (context, mySnap) {
                    final myTickets = mySnap.data ?? const <ConsumerTicket>[];
                    final hasTicket = myTickets.isNotEmpty;

                    final isHost = details.hostUserId.isNotEmpty && details.hostUserId == (FirebaseAuth.instance.currentUser?.uid ?? '');
                    final isLive = details.isLive;
                    final canJoinNow = isLive && details.isOnline;

                    // CTA precedence:
                    // - Host: Manage Event (when not live)
                    // - If live+online: Join Now
                    // - If ticket exists: show QR
                    // - Else: Buy Ticket
                    if (isHost && !isLive) {
                      return _PrimaryButton(
                        label: 'Manage Event',
                        busy: false,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Manage Event is coming soon.')),
                          );
                        },
                      );
                    }

                    if (canJoinNow) {
                      return _PrimaryButton(
                        label: 'Join Now',
                        busy: false,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Join for events is coming soon.')),
                          );
                        },
                      );
                    }

                    if (hasTicket) {
                      final first = myTickets.first;
                      return GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Your Ticket', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 12),
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(10),
                                  child: QrImageView(
                                    data: first.qrCode,
                                    size: 220,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Status: ${first.status}',
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      );
                    }

                    return FutureBuilder<List<EventTicketType>>(
                      future: _ticketTypesFuture,
                      builder: (context, typesSnap) {
                        final types = typesSnap.data ?? const <EventTicketType>[];
                        final chosenId = _selectedTicketId?.trim() ?? '';

                        if (types.isEmpty) {
                          return _PrimaryButton(
                            label: 'Buy Ticket',
                            busy: _buying,
                            onPressed: null,
                          );
                        }

                        final chosen = types.firstWhere(
                          (t) => t.id == chosenId,
                          orElse: () => types.first,
                        );

                        return _PrimaryButton(
                          label: 'Buy Ticket',
                          busy: _buying,
                          onPressed: () => _buyTicket(details: details, selectedType: chosen),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    required this.busy,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.stageGold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.details});

  final _EventDetails details;

  @override
  Widget build(BuildContext context) {
    final cover = details.coverUrl.trim();
    final title = details.title.trim();
    final subtitle = details.subtitle.trim();
    final host = details.hostName.trim();

    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: cover.isNotEmpty
                  ? Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.surface2,
                        child: const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
                      ),
                    )
                  : Container(
                      color: AppColors.surface2,
                      child: const Center(child: Icon(Icons.event, color: AppColors.textMuted)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: details.isLive
                            ? AppColors.brandPink.withValues(alpha: 0.16)
                            : AppColors.stageGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (details.isLive ? AppColors.brandPink : AppColors.stageGold).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        details.isLive ? 'LIVE' : 'EVENT',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title.isNotEmpty ? title : 'Event',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
                ],
                if (host.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Host: $host', style: const TextStyle(color: AppColors.textMuted)),
                ],
                if (details.startsAt != null) ...[
                  const SizedBox(height: 6),
                  Text('Starts: ${details.startsAtLabel}', style: const TextStyle(color: AppColors.textMuted)),
                ],
                if (details.location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(details.location, style: const TextStyle(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetails {
  const _EventDetails({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.coverUrl,
    required this.hostUserId,
    required this.hostName,
    required this.startsAt,
    required this.isLive,
    required this.isOnline,
    required this.location,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String coverUrl;
  final String hostUserId;
  final String hostName;
  final DateTime? startsAt;
  final bool isLive;
  final bool isOnline;
  final String location;

  String get startsAtLabel => startsAt == null ? '' : _fmt(startsAt!);

  static String _fmt(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  factory _EventDetails.fromModel(LiveEvent event, {required Map<String, dynamic> row}) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final title = s(row['title']).isNotEmpty
        ? s(row['title'])
        : (s(row['name']).isNotEmpty ? s(row['name']) : event.title);

    final cover = s(row['poster_url']).isNotEmpty
        ? s(row['poster_url'])
        : (s(row['cover_image_url']).isNotEmpty
            ? s(row['cover_image_url'])
            : (event.coverImageUrl ?? ''));

    final hostName = s(row['host_name']).isNotEmpty ? s(row['host_name']) : (event.hostName ?? '');
    final hostUserId = s(row['host_user_id']).isNotEmpty
        ? s(row['host_user_id'])
        : (s(row['artist_id']).isNotEmpty ? s(row['artist_id']) : (event.hostUserId ?? ''));

    DateTime? starts;
    final startRaw = row['starts_at'] ?? row['date_time'] ?? row['scheduled_at'] ?? row['start_time'] ?? row['created_at'];
    if (startRaw != null) {
      starts = DateTime.tryParse(startRaw.toString());
    }

    final isLiveRaw = row['is_live'] ?? row['live'] ?? event.isLive;
    final isLive = isLiveRaw is bool ? isLiveRaw : (isLiveRaw?.toString().toLowerCase() == 'true' || isLiveRaw?.toString() == '1');

    final onlineRaw = row['is_online'] ?? row['isOnline'] ?? event.isOnline;
    final isOnline = onlineRaw is bool ? onlineRaw : (onlineRaw?.toString().toLowerCase() == 'true' || onlineRaw?.toString() == '1');

    final location = s(row['location']).isNotEmpty
        ? s(row['location'])
        : (s(row['venue']).isNotEmpty ? s(row['venue']) : (s(row['city']).isNotEmpty ? s(row['city']) : ''));

    return _EventDetails(
      id: s(row['id']).isNotEmpty ? s(row['id']) : event.id,
      title: title,
      subtitle: s(row['subtitle']).isNotEmpty ? s(row['subtitle']) : (event.subtitle ?? ''),
      description: s(row['description']).isNotEmpty ? s(row['description']) : '',
      coverUrl: cover,
      hostUserId: hostUserId,
      hostName: hostName,
      startsAt: starts ?? event.startsAt,
      isLive: isLive,
      isOnline: isOnline,
      location: location,
    );
  }
}
