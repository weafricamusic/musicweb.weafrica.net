import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../services/ads/unified_ad_service.dart';
import '../../../services/creator_finance_api.dart';

class EarnCoinsScreen extends StatefulWidget {
  const EarnCoinsScreen({super.key});

  @override
  State<EarnCoinsScreen> createState() => _EarnCoinsScreenState();
}

class _EarnCoinsScreenState extends State<EarnCoinsScreen> {
  bool _loading = false;
  double _awarded = 0;

  late Future<CreatorWalletSummary> _walletFuture;

  @override
  void initState() {
    super.initState();
    _walletFuture = const CreatorFinanceApi().fetchMyWalletSummary();
  }

  Future<void> _watch() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _awarded = 0;
    });

    try {
      final coins = await UnifiedAdService.instance.showRewardedForCoins(context);
      if (!mounted) return;

      setState(() => _awarded = coins);

      if (coins > 0) {
        setState(() {
          _walletFuture = const CreatorFinanceApi().fetchMyWalletSummary();
        });
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('You earned +${coins.toStringAsFixed(0)} coins.')));
      } else {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('No reward earned. Please try again.')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earn Coins'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Watch a short ad and earn coins.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Coins will be added to your wallet after you finish watching.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _watch,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(_loading ? 'Loading ad…' : 'Watch Ad'),
            ),
            const SizedBox(height: 14),
            FutureBuilder<CreatorWalletSummary>(
              future: _walletFuture,
              builder: (context, snap) {
                final bal = snap.data?.coinBalance;
                if (bal == null) return const SizedBox.shrink();
                return Text(
                  'Wallet coins: ${bal.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                );
              },
            ),
            if (_awarded > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Last reward: +${_awarded.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
