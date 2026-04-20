import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../services/creator_finance_api.dart';
import '../../auth/user_role.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../dj_dashboard/models/dj_dashboard_models.dart';
import '../../dj_dashboard/services/dj_dashboard_service.dart';

class CreatorEarningsHubScreen extends StatefulWidget {
  const CreatorEarningsHubScreen({
    super.key,
    required this.role,
    this.showAppBar = true,
  });

  final UserRole role;
  final bool showAppBar;

  @override
  State<CreatorEarningsHubScreen> createState() => _CreatorEarningsHubScreenState();
}

class _CreatorEarningsHubScreenState extends State<CreatorEarningsHubScreen> {
  static const int _minConvertCoins = 100;
  static const double _coinsPerMwk = 2.0; // 100 coins = MWK 50.00

  final _finance = const CreatorFinanceApi();
  final _djService = DjDashboardService();

  late Future<_HubData> _future;
  bool _busy = false;

  String get _destinationOwnerType {
    return switch (widget.role) {
      UserRole.dj => 'dj',
      _ => 'artist',
    };
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HubData> _load() async {
    final decision = await CreatorEntitlementGate.instance.check(
      role: widget.role,
      capability: CreatorCapability.monetization,
    );
    if (!decision.allowed) {
      return _HubData.locked(decision);
    }

    final summary = await _finance.fetchMyWalletSummary();
    final transactions = await _finance.fetchMyWalletTransactions(limit: 200);
    final withdrawals = await _finance.fetchMyWithdrawals(limit: 200);

    _PayoutMethods payoutMethods = const _PayoutMethods.empty();
    if (widget.role == UserRole.dj) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if ((uid ?? '').trim().isNotEmpty) {
        final profile = await _djService.getProfile(djUid: uid!);
        payoutMethods = _PayoutMethods.fromDjProfile(profile);
      }
    } else {
      payoutMethods = await _loadPayoutMethodsFromSupabase();
    }

    return _HubData(
      summary: summary,
      transactions: transactions,
      withdrawals: withdrawals,
      payoutMethods: payoutMethods,
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  String _formatMwk(num v) {
    final n = v.toDouble();
    final s = n.toStringAsFixed(2);
    return 'MWK $s';
  }

  Widget _moneyAnimated(String text, TextStyle? style) {
    final stripped = text.replaceAll(RegExp(r'[^0-9.]'), '');
    final value = double.tryParse(stripped) ?? 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final formatted = text.contains('MWK') ? _formatMwk(v) : v.toStringAsFixed(0);
        return Text(formatted, style: style);
      },
    );
  }

  Future<void> _convertCoins({required _HubData data}) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.role,
      capability: CreatorCapability.withdraw,
    );
    if (!allowed || !mounted) return;

    final maxCoins = data.summary.coinBalance.floor();
    if (maxCoins < _minConvertCoins) {
      _snack('You need at least $_minConvertCoins coins to convert.');
      return;
    }

    final coinsCtrl = TextEditingController(text: _minConvertCoins.toString());

    final coins = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;

        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Convert coins',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(ctx).pop(null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Rate: 100 coins = MWK ${(100 / _coinsPerMwk).toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: coinsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Coins',
                  helperText: 'Min: $_minConvertCoins • Max: $maxCoins',
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final v = int.tryParse(coinsCtrl.text.trim());
                    if (v == null || v < _minConvertCoins || v > maxCoins) return;
                    Navigator.of(ctx).pop(v);
                  },
                  child: const Text('Convert'),
                ),
              ),
            ],
          ),
        );
      },
    );

    coinsCtrl.dispose();

    if (!mounted) return;
    if (coins == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').trim().isEmpty) {
      _snack('Please sign in again.');
      return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'convert_coins_to_cash',
        params: {
          'p_user_id': uid,
          'p_coins': coins,
          'p_conversion_rate': _coinsPerMwk,
        },
      );

      if (!mounted) return;
      _snack('Converted $coins coins to cash.');
      setState(() {
        _future = _load();
      });
    } catch (e, st) {
      UserFacingError.log('CreatorEarningsHubScreen convert coins failed', e, st);
      _snack('Could not convert coins. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_PayoutMethods?> _editPaymentMethods(_PayoutMethods methods) async {
    if (widget.role == UserRole.dj) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if ((uid ?? '').trim().isEmpty) {
        _snack('Please sign in again.');
        return null;
      }

      final profile = await _djService.getProfile(djUid: uid!);
      if (!mounted) return null;

      final updated = await showModalBottomSheet<_PayoutMethods>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (ctx) => _PaymentMethodsSheet(
          role: widget.role,
          initial: _PayoutMethods.fromDjProfile(profile),
        ),
      );

      if (updated == null) return null;

      try {
        await _djService.upsertProfile(
          djUid: uid,
          stageName: profile?.stageName,
          country: profile?.country,
          bio: profile?.bio,
          profilePhoto: profile?.profilePhoto,
          bankAccount: updated.bank?.toOneLineString(),
          mobileMoneyPhone: updated.mobileMoney?.phone,
        );
      } catch (e, st) {
        UserFacingError.log('CreatorEarningsHubScreen save dj payout methods failed', e, st);
        _snack('Could not save payment methods.');
        return null;
      }

      return updated;
    }

    final updated = await showModalBottomSheet<_PayoutMethods>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _PaymentMethodsSheet(
        role: widget.role,
        initial: methods,
      ),
    );

    if (updated == null) return null;
    try {
      await _savePayoutMethodsToSupabase(updated);
    } catch (e, st) {
      UserFacingError.log('CreatorEarningsHubScreen save artist payout methods failed', e, st);
      _snack('Could not save payment methods.');
      return null;
    }
    return updated;
  }

  Future<_PayoutMethods> _loadPayoutMethodsFromSupabase() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').trim().isEmpty) return const _PayoutMethods.empty();

    try {
      final rows = await Supabase.instance.client
          .from('payout_destinations')
          .select(
            'kind,label,bank_name,bank_account_name,bank_account_number,bank_branch,mobile_network,mobile_number,mobile_account_name,is_default',
          )
          .eq('owner_type', _destinationOwnerType)
          .eq('owner_id', uid!)
          .order('is_default', ascending: false)
          .order('updated_at', ascending: false)
          .limit(10);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
      if (list.isEmpty) return const _PayoutMethods.empty();

      _BankMethod? bank;
      _MobileMoneyMethod? mobileMoney;
      _PayoutMethodKey? defaultKey;

      for (final row in list) {
        final kind = (row['kind'] ?? '').toString().trim();
        final isDefault = row['is_default'] == true;

        if (kind == 'bank' && bank == null) {
          bank = _BankMethod(
            accountHolderName: (row['bank_account_name'] ?? '').toString(),
            bankName: (row['bank_name'] ?? row['label'] ?? '').toString(),
            accountNumber: (row['bank_account_number'] ?? '').toString(),
            branchCode: (row['bank_branch'] ?? '').toString(),
          );
          if (isDefault) defaultKey = _PayoutMethodKey.bank;
        }

        if (kind == 'mobile_money' && mobileMoney == null) {
          mobileMoney = _MobileMoneyMethod(
            provider: (row['mobile_network'] ?? row['label'] ?? '').toString(),
            phone: (row['mobile_number'] ?? '').toString(),
            accountName: (row['mobile_account_name'] ?? '').toString(),
          );
          if (isDefault) defaultKey = _PayoutMethodKey.mobileMoney;
        }
      }

      return _PayoutMethods(
        bank: bank,
        mobileMoney: mobileMoney,
        defaultKey: defaultKey,
      );
    } catch (e, st) {
      UserFacingError.log('CreatorEarningsHubScreen load payout methods failed', e, st);
      return const _PayoutMethods.empty();
    }
  }

  Future<void> _savePayoutMethodsToSupabase(_PayoutMethods methods) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').trim().isEmpty) {
      throw StateError('Missing current user');
    }

    final ownerType = _destinationOwnerType;
    final defaultKey = methods.effectiveDefault;
    final client = Supabase.instance.client;

    await client.from('payout_destinations').delete().eq('owner_type', ownerType).eq('owner_id', uid!);

    final rows = <Map<String, dynamic>>[];

    final bank = methods.bank;
    if (bank != null) {
      rows.add({
        'owner_type': ownerType,
        'owner_id': uid,
        'kind': 'bank',
        'label': bank.label,
        'bank_name': bank.bankName.trim(),
        'bank_account_name': bank.accountHolderName.trim(),
        'bank_account_number': bank.accountNumber.trim(),
        'bank_branch': bank.branchCode.trim(),
        'is_default': defaultKey == _PayoutMethodKey.bank,
        'meta': const <String, dynamic>{'source': 'creator_earnings_hub'},
      });
    }

    final mobile = methods.mobileMoney;
    if (mobile != null) {
      rows.add({
        'owner_type': ownerType,
        'owner_id': uid,
        'kind': 'mobile_money',
        'label': mobile.label,
        'mobile_network': mobile.provider.trim(),
        'mobile_number': mobile.phone.trim(),
        'mobile_account_name': mobile.accountName.trim(),
        'is_default': defaultKey == _PayoutMethodKey.mobileMoney,
        'meta': const <String, dynamic>{'source': 'creator_earnings_hub'},
      });
    }

    if (rows.isNotEmpty) {
      await client.from('payout_destinations').insert(rows);
    }
  }

  Future<void> _requestWithdrawal(_HubData data) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: widget.role,
      capability: CreatorCapability.withdraw,
    );
    if (!allowed || !mounted) return;

    final methods = data.payoutMethods;
    if (!methods.hasAny) {
      _snack('Please set up a payment method first.');
      return;
    }

    final res = await showModalBottomSheet<_WithdrawalRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _WithdrawalRequestSheet(
        cashMwk: data.summary.cashBalanceFor('MWK'),
        coins: data.summary.coinBalance,
        methods: methods,
      ),
    );

    if (res == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').trim().isEmpty) {
      _snack('Please sign in again.');
      return;
    }

    setState(() => _busy = true);

    try {
      if (res.source == _WithdrawalSource.coins) {
        final neededCoins = (res.amountMwk * _coinsPerMwk).ceil();
        if (neededCoins < _minConvertCoins) {
          throw StateError('Minimum conversion is $_minConvertCoins coins');
        }

        await Supabase.instance.client.rpc(
          'convert_coins_to_cash',
          params: {
            'p_user_id': uid,
            'p_coins': neededCoins,
            'p_conversion_rate': _coinsPerMwk,
          },
        );
      }

      await _finance.requestWithdrawal(
        amount: res.amountMwk,
        currency: 'MWK',
        paymentMethod: res.methodKey,
        accountDetails: res.accountDetails,
      );

      if (!mounted) return;
      _snack('Withdrawal request submitted.');
      setState(() {
        _future = _load();
      });
    } catch (e, st) {
      UserFacingError.log('CreatorEarningsHubScreen request withdrawal failed', e, st);
      _snack('Could not submit withdrawal. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openHistory(_HubData data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _HistorySheet(
        transactions: data.transactions,
        withdrawals: data.withdrawals,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subs = SubscriptionsController.instance;

    return AnimatedBuilder(
      animation: subs,
      builder: (context, _) {
        return Scaffold(
          appBar: widget.showAppBar
              ? AppBar(
                  title: const Text('Earnings Hub'),
                  actions: [
                    IconButton(
                      tooltip: 'Payment methods',
                      onPressed: _busy
                          ? null
                          : () async {
                              final snap = await _future;
                              if (!mounted) return;
                              if (snap.lockedDecision != null) return;

                              final updated = await _editPaymentMethods(snap.payoutMethods);
                              if (!mounted || updated == null) return;

                              setState(() {
                                _future = _load();
                              });
                            },
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                )
              : null,
          body: FutureBuilder<_HubData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return _ErrorState(
                  message: 'Could not load earnings.',
                  onRetry: () => setState(() => _future = _load()),
                );
              }

              final data = snap.data ?? _HubData.empty();
              final locked = data.lockedDecision;
              if (locked != null) {
                return _LockedState(
                  title: locked.title,
                  message: locked.message,
                  showUpgrade: locked.offerUpgrade,
                  onRetry: () => setState(() => _future = _load()),
                  onOpenPlans: () async {
                    await CreatorEntitlementGate.instance.ensureAllowed(
                      context,
                      role: widget.role,
                      capability: CreatorCapability.monetization,
                    );
                    if (!mounted) return;
                    setState(() => _future = _load());
                  },
                );
              }

              final totalEarned = data.summary.totalEarned;
              final cashMwk = data.summary.cashBalanceFor('MWK');
              final coins = data.summary.coinBalance;
              final coinsValueMwk = coins / _coinsPerMwk;

              return RefreshIndicator(
                color: AppColors.brandOrange,
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _Card(
                      child: Row(
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: AppColors.brandOrange.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: AppColors.brandOrange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL EARNINGS',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _moneyAnimated(
                                  _formatMwk(totalEarned),
                                  Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'All-time earnings from your music',
                                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c) {
                        final isNarrow = c.maxWidth < 520;
                        final cards = [
                          _Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CASH',
                                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 10),
                                _moneyAnimated(
                                  _formatMwk(cashMwk),
                                  Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Ready to withdraw',
                                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _requestWithdrawal(data),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: const Text('Request withdrawal'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'COINS',
                                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  coins.toStringAsFixed(0),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '≈ ${_formatMwk(coinsValueMwk)}',
                                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _convertCoins(data: data),
                                    icon: const Icon(Icons.currency_exchange),
                                    label: const Text('Convert'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ];

                        if (isNarrow) {
                          return Column(
                            children: [
                              cards[0],
                              const SizedBox(height: 12),
                              cards[1],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(Icons.credit_card_outlined, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('PAYMENT METHODS', style: TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 6),
                                Text(
                                  data.payoutMethods.hasAny
                                      ? 'Bank: ${data.payoutMethods.bank?.maskedHint() ?? 'Not set'}\nMobile: ${data.payoutMethods.mobileMoney?.maskedHint() ?? 'Not set'}'
                                      : 'No payment method saved yet.',
                                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final updated = await _editPaymentMethods(data.payoutMethods);
                                    if (!mounted || updated == null) return;
                                    setState(() {
                                      _future = _load();
                                    });
                                  },
                            child: Text(data.payoutMethods.hasAny ? 'Manage' : 'Set up'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'REQUEST WITHDRAWAL',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Choose cash or coins and send to your saved method.',
                                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _requestWithdrawal(data),
                            child: const Text('Withdraw'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Row(
                        children: [
                          const Icon(Icons.bar_chart, color: AppColors.textMuted),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'TRANSACTION HISTORY',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openHistory(data),
                            child: const Text('View'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _HistoryPreview(
                      transactions: data.transactions,
                      withdrawals: data.withdrawals,
                      onOpenAll: () => _openHistory(data),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _HubData {
  const _HubData({
    required this.summary,
    required this.transactions,
    required this.withdrawals,
    required this.payoutMethods,
  }) : lockedDecision = null;

  const _HubData.locked(this.lockedDecision)
      : summary = const CreatorWalletSummary(
          userId: '',
          coinBalance: 0,
          totalEarned: 0,
          cashBalances: <String, double>{'MWK': 0, 'USD': 0, 'ZAR': 0},
          updatedAt: '',
        ),
        transactions = const <Map<String, dynamic>>[],
        withdrawals = const <Map<String, dynamic>>[],
        payoutMethods = const _PayoutMethods.empty();

  factory _HubData.empty() => const _HubData(
        summary: CreatorWalletSummary(
          userId: '',
          coinBalance: 0,
          totalEarned: 0,
          cashBalances: <String, double>{'MWK': 0, 'USD': 0, 'ZAR': 0},
          updatedAt: '',
        ),
        transactions: <Map<String, dynamic>>[],
        withdrawals: <Map<String, dynamic>>[],
        payoutMethods: _PayoutMethods.empty(),
      );

  final CreatorWalletSummary summary;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> withdrawals;
  final _PayoutMethods payoutMethods;

  final CreatorGateDecision? lockedDecision;
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _HistoryPreview extends StatelessWidget {
  const _HistoryPreview({
    required this.transactions,
    required this.withdrawals,
    required this.onOpenAll,
  });

  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> withdrawals;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty && withdrawals.isEmpty) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No activity yet.', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
              'When you receive gifts, stream earnings, or make withdrawals, they will appear here.',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onOpenAll, child: const Text('View history')),
            ),
          ],
        ),
      );
    }

    final items = <_HistoryItem>[];
    for (final t in transactions.take(6)) {
      items.add(_HistoryItem.fromTransaction(t));
    }
    for (final w in withdrawals.take(4)) {
      items.add(_HistoryItem.fromWithdrawal(w));
    }
    items.sort((a, b) => b.when.compareTo(a.when));

    return _Card(
      child: Column(
        children: [
          for (final item in items.take(6)) ...[
            _HistoryRow(item: item),
            if (item != items.take(6).last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final _HistoryItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(item.icon, size: 18, color: AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (item.subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 2),
              Text(
                item.when.toLocal().toString().split('.').first,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(item.amountLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _HistoryItem {
  const _HistoryItem({
    required this.when,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
  });

  final DateTime when;
  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;

  static DateTime _parseDate(Object? v) {
    final s = (v ?? '').toString();
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory _HistoryItem.fromTransaction(Map<String, dynamic> row) {
    final type = (row['type'] ?? '').toString().trim();
    final amount = (row['amount'] ?? 0);
    final amt = (amount is num) ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0;

    final currency = (row['currency'] ?? '').toString().trim().toUpperCase();
    final prefix = (type.toLowerCase() == 'debit') ? '-' : '+';

    final label = currency.isEmpty
        ? '$prefix${amt.toStringAsFixed(2)}'
        : '$prefix${amt.toStringAsFixed(2)} $currency';

    final title = type.isEmpty ? 'Transaction' : type.toUpperCase();
    final desc = (row['description'] ?? '').toString();

    final icon = switch (type.toLowerCase()) {
      'gift' => Icons.card_giftcard,
      'conversion' => Icons.currency_exchange,
      'debit' => Icons.south_east,
      'credit' => Icons.north_east,
      _ => Icons.receipt_long,
    };

    return _HistoryItem(
      when: _parseDate(row['created_at']),
      title: title,
      subtitle: desc,
      amountLabel: label,
      icon: icon,
    );
  }

  factory _HistoryItem.fromWithdrawal(Map<String, dynamic> row) {
    final amount = row['amount'];
    final amt = (amount is num) ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0;
    final currency = (row['currency'] ?? '').toString().trim().toUpperCase();

    final status = (row['status'] ?? 'pending').toString().trim();
    final method = (row['payment_method'] ?? '').toString().trim();

    return _HistoryItem(
      when: _parseDate(row['created_at']),
      title: 'WITHDRAWAL',
      subtitle: '${status.toUpperCase()}${method.isEmpty ? '' : ' • $method'}',
      amountLabel: '-${amt.toStringAsFixed(2)}${currency.isEmpty ? '' : ' $currency'}',
      icon: Icons.payments_outlined,
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.transactions,
    required this.withdrawals,
  });

  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> withdrawals;

  @override
  Widget build(BuildContext context) {
    final items = <_HistoryItem>[];
    for (final t in transactions) {
      items.add(_HistoryItem.fromTransaction(t));
    }
    for (final w in withdrawals) {
      items.add(_HistoryItem.fromWithdrawal(w));
    }
    items.sort((a, b) => b.when.compareTo(a.when));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transaction history',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No transactions yet.',
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        return _Card(child: _HistoryRow(item: items[i]));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _WithdrawalSource { cash, coins }

class _WithdrawalRequest {
  const _WithdrawalRequest({
    required this.source,
    required this.amountMwk,
    required this.methodKey,
    required this.accountDetails,
  });

  final _WithdrawalSource source;
  final double amountMwk;
  final String methodKey;
  final Map<String, dynamic>? accountDetails;
}

class _WithdrawalRequestSheet extends StatefulWidget {
  const _WithdrawalRequestSheet({
    required this.cashMwk,
    required this.coins,
    required this.methods,
  });

  final double cashMwk;
  final double coins;
  final _PayoutMethods methods;

  @override
  State<_WithdrawalRequestSheet> createState() => _WithdrawalRequestSheetState();
}

class _WithdrawalRequestSheetState extends State<_WithdrawalRequestSheet> {
  _WithdrawalSource _source = _WithdrawalSource.cash;
  _PayoutMethodKey _method = _PayoutMethodKey.bank;

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!widget.methods.hasBank && widget.methods.hasMobileMoney) {
      _method = _PayoutMethodKey.mobileMoney;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    final maxCash = widget.cashMwk;
    final coinsValueMwk = widget.coins / _CreatorEarningsHubScreenState._coinsPerMwk;

    final canUseBank = widget.methods.hasBank;
    final canUseMobile = widget.methods.hasMobileMoney;

    final max = _source == _WithdrawalSource.cash ? maxCash : coinsValueMwk;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Request withdrawal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Withdraw from',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                RadioListTile<_WithdrawalSource>(
                  value: _WithdrawalSource.cash,
                  groupValue: _source,
                  onChanged: (v) => setState(() => _source = v ?? _WithdrawalSource.cash),
                  title: Text('Cash balance: MWK ${widget.cashMwk.toStringAsFixed(2)}'),
                  dense: true,
                ),
                RadioListTile<_WithdrawalSource>(
                  value: _WithdrawalSource.coins,
                  groupValue: _source,
                  onChanged: (v) => setState(() => _source = v ?? _WithdrawalSource.cash),
                  title: Text('Coins: ${widget.coins.toStringAsFixed(0)} (≈ MWK ${coinsValueMwk.toStringAsFixed(2)})'),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount (MWK)',
              helperText: 'Max: ${max.toStringAsFixed(2)}',
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Send to',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                if (canUseBank)
                  RadioListTile<_PayoutMethodKey>(
                    value: _PayoutMethodKey.bank,
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v ?? _method),
                    title: Text(widget.methods.bank?.label ?? 'Bank account'),
                    subtitle: Text(widget.methods.bank?.maskedHint() ?? ''),
                    dense: true,
                  ),
                if (canUseMobile)
                  RadioListTile<_PayoutMethodKey>(
                    value: _PayoutMethodKey.mobileMoney,
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v ?? _method),
                    title: Text(widget.methods.mobileMoney?.label ?? 'Mobile money'),
                    subtitle: Text(widget.methods.mobileMoney?.maskedHint() ?? ''),
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final amount = double.tryParse(_amountCtrl.text.trim());
                if (amount == null || amount <= 0) return;
                if (max > 0 && amount > max) return;

                final details = <String, dynamic>{
                  if (_noteCtrl.text.trim().isNotEmpty) 'notes': _noteCtrl.text.trim(),
                };

                if (_method == _PayoutMethodKey.bank) {
                  final bank = widget.methods.bank;
                  if (bank != null) {
                    details['bank_account'] = bank.toOneLineString();
                  }
                } else {
                  final mm = widget.methods.mobileMoney;
                  if (mm != null) {
                    details['mobile_money_phone'] = mm.phone;
                    if (mm.provider.trim().isNotEmpty) details['provider'] = mm.provider;
                    if (mm.accountName.trim().isNotEmpty) details['account_name'] = mm.accountName;
                  }
                }

                Navigator.of(context).pop(
                  _WithdrawalRequest(
                    source: _source,
                    amountMwk: amount,
                    methodKey: _method.apiKey,
                    accountDetails: details.isEmpty ? null : details,
                  ),
                );
              },
              child: const Text('Request withdrawal'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PayoutMethodKey { bank, mobileMoney }

extension on _PayoutMethodKey {
  String get apiKey {
    return switch (this) {
      _PayoutMethodKey.bank => 'bank',
      _PayoutMethodKey.mobileMoney => 'mobile_money',
    };
  }
}

class _PayoutMethods {
  const _PayoutMethods({
    required this.bank,
    required this.mobileMoney,
    required this.defaultKey,
  });

  const _PayoutMethods.empty()
      : bank = null,
        mobileMoney = null,
        defaultKey = null;

  final _BankMethod? bank;
  final _MobileMoneyMethod? mobileMoney;
  final _PayoutMethodKey? defaultKey;

  bool get hasBank => bank != null;
  bool get hasMobileMoney => mobileMoney != null;
  bool get hasAny => hasBank || hasMobileMoney;

  _PayoutMethodKey? get effectiveDefault {
    final d = defaultKey;
    if (d == _PayoutMethodKey.bank && hasBank) return d;
    if (d == _PayoutMethodKey.mobileMoney && hasMobileMoney) return d;
    if (hasBank) return _PayoutMethodKey.bank;
    if (hasMobileMoney) return _PayoutMethodKey.mobileMoney;
    return null;
  }

  static _PayoutMethods fromDjProfile(DjProfile? profile) {
    if (profile == null) return const _PayoutMethods.empty();

    final bankRaw = (profile.bankAccount ?? '').trim();
    final mobileRaw = (profile.mobileMoneyPhone ?? '').trim();

    return _PayoutMethods(
      bank: bankRaw.isEmpty
          ? null
          : _BankMethod(
              accountHolderName: '',
              bankName: '',
              accountNumber: '',
              branchCode: '',
              raw: bankRaw,
            ),
      mobileMoney: mobileRaw.isEmpty
          ? null
          : _MobileMoneyMethod(
              provider: '',
              phone: mobileRaw,
              accountName: '',
            ),
      defaultKey: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'default': defaultKey?.name,
      'bank': bank?.toJson(),
      'mobile_money': mobileMoney?.toJson(),
    };
  }

  static _PayoutMethods fromJson(Map<String, dynamic> json) {
    final def = (json['default'] ?? '').toString().trim();
    _PayoutMethodKey? defaultKey;
    for (final k in _PayoutMethodKey.values) {
      if (k.name == def) defaultKey = k;
    }

    final bank = json['bank'];
    final mm = json['mobile_money'];

    return _PayoutMethods(
      bank: bank is Map ? _BankMethod.fromJson(bank.map((k, v) => MapEntry(k.toString(), v))) : null,
      mobileMoney: mm is Map
          ? _MobileMoneyMethod.fromJson(mm.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      defaultKey: defaultKey,
    );
  }

  _PayoutMethods copyWith({
    _BankMethod? bank,
    _MobileMoneyMethod? mobileMoney,
    _PayoutMethodKey? defaultKey,
    bool clearBank = false,
    bool clearMobileMoney = false,
  }) {
    return _PayoutMethods(
      bank: clearBank ? null : (bank ?? this.bank),
      mobileMoney: clearMobileMoney ? null : (mobileMoney ?? this.mobileMoney),
      defaultKey: defaultKey ?? this.defaultKey,
    );
  }
}

class _BankMethod {
  const _BankMethod({
    required this.accountHolderName,
    required this.bankName,
    required this.accountNumber,
    required this.branchCode,
    this.raw,
  });

  final String accountHolderName;
  final String bankName;
  final String accountNumber;
  final String branchCode;
  final String? raw;

  String get label {
    final n = bankName.trim();
    return n.isEmpty ? 'Bank account' : n;
  }

  String maskedHint() {
    final raw = (accountNumber.trim().isNotEmpty ? accountNumber.trim() : (this.raw ?? '')).trim();
    if (raw.isEmpty) return '';

    final digit = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digit.length <= 4) return digit;
    return '****${digit.substring(digit.length - 4)}';
  }

  String toOneLineString() {
    final r = (raw ?? '').trim();
    if (r.isNotEmpty) return r;

    final parts = <String>[];
    if (bankName.trim().isNotEmpty) parts.add(bankName.trim());
    if (accountHolderName.trim().isNotEmpty) parts.add(accountHolderName.trim());
    if (accountNumber.trim().isNotEmpty) parts.add(accountNumber.trim());
    if (branchCode.trim().isNotEmpty) parts.add('Branch $branchCode');

    return parts.join(' • ');
  }

  Map<String, dynamic> toJson() {
    return {
      'account_holder_name': accountHolderName,
      'bank_name': bankName,
      'account_number': accountNumber,
      'branch_code': branchCode,
    };
  }

  static _BankMethod fromJson(Map<String, dynamic> json) {
    return _BankMethod(
      accountHolderName: (json['account_holder_name'] ?? '').toString(),
      bankName: (json['bank_name'] ?? '').toString(),
      accountNumber: (json['account_number'] ?? '').toString(),
      branchCode: (json['branch_code'] ?? '').toString(),
    );
  }
}

class _MobileMoneyMethod {
  const _MobileMoneyMethod({
    required this.provider,
    required this.phone,
    required this.accountName,
  });

  final String provider;
  final String phone;
  final String accountName;

  String get label {
    final p = provider.trim();
    return p.isEmpty ? 'Mobile money' : p;
  }

  String maskedHint() {
    final p = phone.trim();
    if (p.length <= 4) return p;
    final last = p.substring(p.length - 4);
    return '***$last';
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'phone': phone,
      'account_name': accountName,
    };
  }

  static _MobileMoneyMethod fromJson(Map<String, dynamic> json) {
    return _MobileMoneyMethod(
      provider: (json['provider'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      accountName: (json['account_name'] ?? '').toString(),
    );
  }
}

class _PaymentMethodsSheet extends StatefulWidget {
  const _PaymentMethodsSheet({required this.role, required this.initial});

  final UserRole role;
  final _PayoutMethods initial;

  @override
  State<_PaymentMethodsSheet> createState() => _PaymentMethodsSheetState();
}

class _PaymentMethodsSheetState extends State<_PaymentMethodsSheet> {
  late _PayoutMethods _methods;

  @override
  void initState() {
    super.initState();
    _methods = widget.initial;
  }

  Future<_BankMethod?> _editBank(_BankMethod? current) {
    return showModalBottomSheet<_BankMethod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _BankFormSheet(initial: current),
    );
  }

  Future<_MobileMoneyMethod?> _editMobile(_MobileMoneyMethod? current) {
    return showModalBottomSheet<_MobileMoneyMethod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _MobileMoneyFormSheet(initial: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Payment methods',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_methods.hasBank)
            _Card(
              child: Row(
                children: [
                  const Icon(Icons.account_balance_outlined, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_methods.bank!.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          _methods.bank!.maskedHint(),
                          style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final updated = await _editBank(_methods.bank);
                      if (!mounted) return;
                      if (updated == null) return;
                      setState(() {
                        _methods = _methods.copyWith(bank: updated);
                      });
                    },
                    child: const Text('Edit'),
                  ),
                ],
              ),
            )
          else
            _Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Bank account', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Not set', style: TextStyle(color: AppColors.textMuted)),
                trailing: TextButton(
                  onPressed: () async {
                    final updated = await _editBank(null);
                    if (!mounted) return;
                    if (updated == null) return;
                    setState(() {
                      _methods = _methods.copyWith(bank: updated);
                    });
                  },
                  child: const Text('Add'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_methods.hasMobileMoney)
            _Card(
              child: Row(
                children: [
                  const Icon(Icons.phone_iphone_outlined, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_methods.mobileMoney!.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          _methods.mobileMoney!.maskedHint(),
                          style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final updated = await _editMobile(_methods.mobileMoney);
                      if (!mounted) return;
                      if (updated == null) return;
                      setState(() {
                        _methods = _methods.copyWith(mobileMoney: updated);
                      });
                    },
                    child: const Text('Edit'),
                  ),
                ],
              ),
            )
          else
            _Card(
              child: ListTile(
                leading: const Icon(Icons.phone_iphone_outlined),
                title: const Text('Mobile money', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Not set', style: TextStyle(color: AppColors.textMuted)),
                trailing: TextButton(
                  onPressed: () async {
                    final updated = await _editMobile(null);
                    if (!mounted) return;
                    if (updated == null) return;
                    setState(() {
                      _methods = _methods.copyWith(mobileMoney: updated);
                    });
                  },
                  child: const Text('Add'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_methods),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankFormSheet extends StatefulWidget {
  const _BankFormSheet({this.initial});

  final _BankMethod? initial;

  @override
  State<_BankFormSheet> createState() => _BankFormSheetState();
}

class _BankFormSheetState extends State<_BankFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _holderCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i == null) return;

    _holderCtrl.text = i.accountHolderName;
    _bankCtrl.text = i.bankName;
    _accountCtrl.text = i.accountNumber;
    _confirmCtrl.text = i.accountNumber;
    _branchCtrl.text = i.branchCode;
  }

  @override
  void dispose() {
    _holderCtrl.dispose();
    _bankCtrl.dispose();
    _accountCtrl.dispose();
    _confirmCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add bank account',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _holderCtrl,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Account holder name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _bankCtrl,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Bank name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _accountCtrl,
              validator: _required,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account number'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmCtrl,
              validator: (v) {
                final a = _accountCtrl.text.trim();
                final b = (v ?? '').trim();
                if (b.isEmpty) return 'Required';
                if (a != b) return 'Does not match';
                return null;
              },
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm account number'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _branchCtrl,
              validator: _required,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(labelText: 'Branch code'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(
                    _BankMethod(
                      accountHolderName: _holderCtrl.text.trim(),
                      bankName: _bankCtrl.text.trim(),
                      accountNumber: _accountCtrl.text.trim(),
                      branchCode: _branchCtrl.text.trim(),
                    ),
                  );
                },
                child: const Text('Save account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMoneyFormSheet extends StatefulWidget {
  const _MobileMoneyFormSheet({this.initial});

  final _MobileMoneyMethod? initial;

  @override
  State<_MobileMoneyFormSheet> createState() => _MobileMoneyFormSheetState();
}

class _MobileMoneyFormSheetState extends State<_MobileMoneyFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final _providerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i == null) return;

    _providerCtrl.text = i.provider;
    _phoneCtrl.text = i.phone;
    _confirmCtrl.text = i.phone;
    _nameCtrl.text = i.accountName;
  }

  @override
  void dispose() {
    _providerCtrl.dispose();
    _phoneCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add mobile money',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _providerCtrl,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Provider (Airtel Money, TNM Mpamba, ...)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              validator: _required,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmCtrl,
              validator: (v) {
                final a = _phoneCtrl.text.trim();
                final b = (v ?? '').trim();
                if (b.isEmpty) return 'Required';
                if (a != b) return 'Does not match';
                return null;
              },
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Confirm phone number'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Account name'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(
                    _MobileMoneyMethod(
                      provider: _providerCtrl.text.trim(),
                      phone: _phoneCtrl.text.trim(),
                      accountName: _nameCtrl.text.trim(),
                    ),
                  );
                },
                child: const Text('Save payment method'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState({
    required this.title,
    required this.message,
    required this.showUpgrade,
    required this.onRetry,
    required this.onOpenPlans,
  });

  final String title;
  final String message;
  final bool showUpgrade;
  final VoidCallback onRetry;
  final Future<void> Function() onOpenPlans;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (showUpgrade)
                  FilledButton(
                    onPressed: () => onOpenPlans(),
                    child: const Text('Upgrade now'),
                  ),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
