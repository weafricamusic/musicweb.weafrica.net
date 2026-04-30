import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/widgets/glass_card.dart';
import '../../../../app/widgets/gold_button.dart';
import '../../../subscriptions/models/gifting_tier.dart';
import '../../../subscriptions/services/consumer_entitlement_gate.dart';
import '../../models/gift_model.dart';
import '../../services/gift_service.dart';
import '../../services/live_economy_api.dart';

class GiftSelectionSheet extends StatefulWidget {
  const GiftSelectionSheet({
    super.key,
    required this.competitor1Id,
    required this.competitor1Name,
    required this.competitor2Id,
    required this.competitor2Name,
    required this.onGiftSelected,
  });

  final String competitor1Id;
  final String competitor1Name;
  final String competitor2Id;
  final String competitor2Name;
  final void Function(GiftModel gift, String toHostId) onGiftSelected;

  @override
  State<GiftSelectionSheet> createState() => _GiftSelectionSheetState();
}

class _GiftSelectionSheetState extends State<GiftSelectionSheet> {
  late final Future<List<GiftModel>> _catalogFuture;
  Future<int?>? _balanceFuture;

  String _selectedRecipientId = '';

  @override
  void initState() {
    super.initState();
    _selectedRecipientId = widget.competitor1Id.trim();
    _catalogFuture = GiftService().listCatalog();
    _balanceFuture = LiveEconomyApi().fetchMyCoinBalance();
  }

  void _refreshBalance() {
    setState(() {
      _balanceFuture = LiveEconomyApi().fetchMyCoinBalance();
    });
  }

  bool get _hasCompetitor2 => widget.competitor2Id.trim().isNotEmpty;

  Future<void> _handleGiftTap(GiftModel gift) async {
    final toHostId = _selectedRecipientId.trim().isNotEmpty
        ? _selectedRecipientId.trim()
        : widget.competitor1Id.trim();
    if (toHostId.isEmpty) return;

    final requiredTier = gift.accessTier;
    final allowed = await ConsumerEntitlementGate.instance.ensureGiftTier(
      context,
      requiredTier: requiredTier,
    );
    if (!allowed || !mounted) return;

    int? balance;
    try {
      balance = await (_balanceFuture ?? Future<int?>.value(null));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not verify your coin balance. Please try again.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (balance != null && gift.coinValue > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough coins.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    widget.onGiftSelected(gift, toHostId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final competitor1Id = widget.competitor1Id.trim();
    final competitor2Id = widget.competitor2Id.trim();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'Send a Gift',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BalanceRow(balanceFuture: _balanceFuture, onRefresh: _refreshBalance),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'To',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RecipientChip(
                    label: widget.competitor1Name.trim().isNotEmpty
                        ? widget.competitor1Name.trim()
                        : 'Host',
                    selected: _selectedRecipientId == competitor1Id,
                    onTap: () => setState(() => _selectedRecipientId = competitor1Id),
                  ),
                  if (_hasCompetitor2)
                    _RecipientChip(
                      label: widget.competitor2Name.trim().isNotEmpty
                          ? widget.competitor2Name.trim()
                          : 'Opponent',
                      selected: _selectedRecipientId == competitor2Id,
                      onTap: () => setState(() => _selectedRecipientId = competitor2Id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<GiftModel>>(
                  future: _catalogFuture,
                  builder: (context, snapshot) {
                    final gifts = snapshot.data ?? const <GiftModel>[];
                    if (snapshot.connectionState == ConnectionState.waiting && gifts.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(color: WeAfricaColors.gold),
                      );
                    }

                    if (gifts.isEmpty) {
                      return const Center(
                        child: Text('No gifts available', style: TextStyle(color: Colors.white54)),
                      );
                    }

                    return ListView.separated(
                      itemCount: gifts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final gift = gifts[index];
                        return _GiftRow(
                          gift: gift,
                          onTap: () => _handleGiftTap(gift),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              GoldButton(
                label: 'CLOSE',
                onPressed: () => Navigator.of(context).pop(),
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balanceFuture, required this.onRefresh});

  final Future<int?>? balanceFuture;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.monetization_on, color: WeAfricaColors.gold, size: 18),
        const SizedBox(width: 8),
        FutureBuilder<int?>(
          future: balanceFuture,
          builder: (context, snapshot) {
            final bal = snapshot.data;
            final text = (bal == null)
                ? 'Coins: —'
                : 'Coins: $bal';
            return Text(
              text,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
            );
          },
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Refresh balance',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, color: Colors.white70),
        ),
      ],
    );
  }
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WeAfricaColors.gold.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WeAfricaColors.gold : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WeAfricaColors.gold : Colors.white70,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _GiftRow extends StatelessWidget {
  const _GiftRow({required this.gift, required this.onTap});

  final GiftModel gift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tierLabel = giftAccessTierLabel(gift.accessTier);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: gift.color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(gift.icon, color: gift.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gift.displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$tierLabel • ${gift.coinValue} coins',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}
