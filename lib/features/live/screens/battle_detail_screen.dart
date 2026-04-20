import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../../app/widgets/glass_card.dart';
import '../../../app/widgets/gold_button.dart';
import '../../subscriptions/checkout_webview_screen.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../services/battle_tickets_api.dart';

enum BattleDetailMode {
  live,
  upcoming,
  replay,
}

class BattleDetailScreen extends StatefulWidget {
  const BattleDetailScreen({
    super.key,
    required this.row,
    required this.mode,
    this.onPrimaryAction,
  });

  final Map<String, dynamic> row;
  final BattleDetailMode mode;

  /// For live/upcoming battles: watch/join action.
  final Future<void> Function()? onPrimaryAction;

  @override
  State<BattleDetailScreen> createState() => _BattleDetailScreenState();
}

class _BattleDetailScreenState extends State<BattleDetailScreen> {
  late final Future<List<Map<String, dynamic>>> _ticketsFuture;

  String _battleIdFromChannel(String channelId) {
    final c = channelId.trim();
    const prefix = 'weafrica_battle_';
    if (!c.startsWith(prefix)) return '';
    return c.substring(prefix.length).trim();
  }

  String _battleId() {
    final direct = (widget.row['battle_id'] ?? widget.row['battleId'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final channelId = (widget.row['channel_id'] ?? widget.row['channelId'] ?? '').toString().trim();
    return _battleIdFromChannel(channelId);
  }

  String _tierLabel(String tier) {
    final t = tier.trim().toLowerCase();
    if (t == 'vip') return 'VIP Ticket';
    if (t == 'priority') return 'Priority Ticket';
    return 'Standard Ticket';
  }

  bool _battlePriorityAllowsTier({
    required String battlePriority,
    required String tier,
  }) {
    final p = battlePriority.trim().toLowerCase();
    final t = tier.trim().toLowerCase();
    if (t == 'standard') return true;
    if (t == 'vip') return p == 'standard' || p == 'priority';
    if (t == 'priority') return p == 'priority';
    return false;
  }

  String _requiredPlanLabelForTier(String tier) {
    final t = tier.trim().toLowerCase();
    if (t == 'vip') return 'Premium required';
    if (t == 'priority') return 'Platinum required';
    return '';
  }

  Future<List<Map<String, dynamic>>> _loadTickets() async {
    final bid = _battleId();
    if (bid.isEmpty) return const [];

    final api = BattleTicketsApi();
    final rows = await api.listBattleTickets(battleId: bid);

    final out = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final tier = (raw['tier'] ?? '').toString().trim().toLowerCase();
      if (tier.isEmpty) continue;

      final available = raw['is_available'];
      final isAvailable = available is bool
          ? available
          : available.toString().trim().toLowerCase() == 'true';
      if (!isAvailable) continue;

      final priceRaw = raw['price_amount'];
      final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(priceRaw.toString()) ?? 0;
      if (!price.isFinite || price <= 0) continue;

      final currency = (raw['price_currency'] ?? 'MWK').toString().trim().toUpperCase();
      if (currency.isEmpty) continue;

      final remainingRaw = raw['remaining'];
      final remaining = (remainingRaw is num)
          ? remainingRaw.toInt()
          : int.tryParse(remainingRaw.toString()) ?? 0;
      if (remaining <= 0) continue;

      out.add(<String, dynamic>{
        'tier': tier,
        'price': price,
        'currency': currency,
        'remaining': remaining,
      });
    }

    out.sort((a, b) {
      final ta = a['tier'].toString();
      final tb = b['tier'].toString();
      int order(String t) {
        switch (t.trim().toLowerCase()) {
          case 'standard':
            return 1;
          case 'vip':
            return 2;
          case 'priority':
            return 3;
        }
        return 9;
      }

      return order(ta).compareTo(order(tb));
    });

    return out;
  }

  Future<void> _buyTicket(String tier) async {
    final bid = _battleId();
    if (bid.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to buy a battle ticket.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    final subs = SubscriptionsController.instance;
    await subs.initialize();
    try {
      await subs.refreshMe();
    } catch (_) {
      // ignore
    }

    final battlePriority = subs.entitlements.effectiveBattlePriority;
    final allowed = _battlePriorityAllowsTier(
      battlePriority: battlePriority,
      tier: tier,
    );

    if (!allowed) {
      if (!mounted) return;
      final req = _requiredPlanLabelForTier(tier);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(req.isEmpty ? 'Upgrade required for this ticket tier.' : req),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    final api = BattleTicketsApi();
    try {
      final session = await api.startBattleTicketPurchase(battleId: bid, tier: tier);
      if (!mounted) return;

      // Already owned.
      if (session.alreadyOwned) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket already owned.')),
        );
        return;
      }

      final checkout = session.checkoutUrl;
      if (checkout == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checkout link missing. Please try again.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
        return;
      }

      final outcome = await Navigator.of(context).push<CheckoutOutcome>(
        MaterialPageRoute<CheckoutOutcome>(
          builder: (_) => CheckoutWebviewScreen(initialUrl: checkout),
        ),
      );

      if (!mounted) return;
      if (outcome != CheckoutOutcome.completed) return;

      if (session.txRef.trim().isNotEmpty) {
        for (var i = 0; i < 4; i++) {
          try {
            final ok = await api.verifyPayChanguPayment(txRef: session.txRef);
            if (ok) break;
          } catch (_) {
            // Ignore and retry briefly; webhook/manual verify races are expected.
          }
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }

      final hasAfter = await api.hasBattleTicket(battleId: bid);
      if (!mounted) return;

      if (!hasAfter) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment is still processing. Please try again shortly.'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket purchased.')),
      );

      // If user came here to watch/join, allow a one-tap continuation.
      if (widget.onPrimaryAction != null && widget.mode == BattleDetailMode.live) {
        await widget.onPrimaryAction!.call();
      }

      setState(() {
        _ticketsFuture = _loadTickets();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _ticketsFuture = _loadTickets();

    // Warm subscription state so plan-gating is accurate.
    final subs = SubscriptionsController.instance;
    subs.initialize().then((_) {
      if (FirebaseAuth.instance.currentUser != null) {
        subs.refreshMe();
      }
    });
  }

  String _title() {
    return (widget.row['title'] ?? '').toString().trim();
  }

  String _hostName() {
    return (widget.row['host_name'] ?? widget.row['hostName'] ?? '').toString().trim();
  }

  String _category() {
    return (widget.row['category'] ?? '').toString().trim();
  }

  String _when() {
    Object? raw;
    switch (widget.mode) {
      case BattleDetailMode.live:
        raw = widget.row['started_at'];
        break;
      case BattleDetailMode.upcoming:
        raw = widget.row['scheduled_at'];
        break;
      case BattleDetailMode.replay:
        raw = widget.row['ended_at'] ?? widget.row['started_at'];
        break;
    }
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');

    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final title = _title();
    final host = _hostName();
    final category = _category();
    final when = _when();

    final subs = SubscriptionsController.instance;

    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      appBar: AppBar(
        title: const Text('BATTLE'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Battle' : title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (host.isNotEmpty) host,
                    if (category.isNotEmpty) category,
                    if (when.isNotEmpty) when,
                  ].join(' • '),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                if (widget.onPrimaryAction != null)
                  GoldButton(
                    label: switch (widget.mode) {
                      BattleDetailMode.live => 'WATCH',
                      BattleDetailMode.upcoming => 'JOIN WHEN LIVE',
                      BattleDetailMode.replay => 'WATCH',
                    },
                    fullWidth: true,
                    onPressed: () async {
                      await widget.onPrimaryAction!.call();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ticket Tiers',
            style: TextStyle(color: WeAfricaColors.gold, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _ticketsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: WeAfricaColors.gold),
                  ),
                );
              }

              final tickets = snap.data ?? const <Map<String, dynamic>>[];
              if (tickets.isEmpty) {
                return const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No ticket tiers available yet.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return AnimatedBuilder(
                animation: subs,
                builder: (context, _) {
                  final battlePriority = subs.entitlements.effectiveBattlePriority;

                  return Column(
                    children: [
                      for (final t in tickets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tierLabel(t['tier'].toString()),
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${t['currency']} ${t['price']} • ${t['remaining']} left',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      if (!_battlePriorityAllowsTier(
                                        battlePriority: battlePriority,
                                        tier: t['tier'].toString(),
                                      ))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            _requiredPlanLabelForTier(t['tier'].toString()),
                                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 120,
                                  child: GoldButton(
                                    size: ButtonSize.small,
                                    label: _battlePriorityAllowsTier(
                                      battlePriority: battlePriority,
                                      tier: t['tier'].toString(),
                                    )
                                        ? 'Buy'
                                        : _requiredPlanLabelForTier(t['tier'].toString())
                                            .replaceAll(' required', ''),
                                    onPressed: _battlePriorityAllowsTier(
                                      battlePriority: battlePriority,
                                      tier: t['tier'].toString(),
                                    )
                                        ? () => _buyTicket(t['tier'].toString())
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
