import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/network/api_uri_builder.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/theme.dart';
import '../../services/creator_finance_api.dart';
import '../auth/user_role.dart';
import '../auth/user_role_resolver.dart';
import '../dj_dashboard/screens/dj_earnings_screen.dart';
import '../artist_dashboard/screens/artist_earnings_screen.dart';
import '../live/screens/live_feed_screen.dart';
import '../subscriptions/services/creator_entitlement_gate.dart';
import '../ads/screens/earn_coins_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.roleOverride});

  final UserRole? roleOverride;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _scrollController = ScrollController();
  final _packagesKey = GlobalKey();

  late Future<_WalletData> _future;

  String? _pendingTopupTxRef;
  bool _verifyingPendingTopup = false;
  late final _LifecycleObserver _lifecycle;

  @override
  void initState() {
    super.initState();
    _future = _load();

    _lifecycle = _LifecycleObserver(
      onResumed: () => unawaited(_onAppResumed()),
    );
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onAppResumed() async {
    final txRef = (_pendingTopupTxRef ?? '').trim();
    if (txRef.isEmpty) return;
    if (_verifyingPendingTopup) return;

    _verifyingPendingTopup = true;
    try {
      final verified = await _verifyTopupWithRetry(txRef);
      if (verified) {
        _pendingTopupTxRef = null;
      }
      await _refresh();
    } finally {
      _verifyingPendingTopup = false;
    }
  }

  Future<_WalletData> _load() async {
    final role = widget.roleOverride ?? await UserRoleResolver.resolveCurrentUser();
    final finance = const CreatorFinanceApi();

    final summary = await finance.fetchMyWalletSummary();
    final tx = await finance.fetchMyWalletTransactions(limit: 60);
    final packages = await const _CoinTopupApi().fetchPackages();

    return _WalletData(
      roleForUi: role,
      summary: summary,
      transactions: tx,
      packages: packages,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _startTopup(_CoinPackage pkg) async {
    try {
      final session = await const _CoinTopupApi().startPayChanguCheckout(packageId: pkg.id);
      if (!mounted) return;

      // PayChangu checkout is more reliable via OS in-app browser (Chrome Custom Tab / SFSafariViewController)
      // than an embedded WebView, especially for mobile money flows that may trigger external intents.
      _pendingTopupTxRef = session.txRef.trim().isEmpty ? null : session.txRef.trim();

      final okInApp = await launchUrl(session.checkoutUrl, mode: LaunchMode.inAppBrowserView);
      if (!okInApp) {
        final okExternal = await launchUrl(session.checkoutUrl, mode: LaunchMode.externalApplication);
        if (!okExternal) {
          throw Exception('Could not open checkout URL');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Complete payment, then return to WeAfrica to confirm your coin balance.')),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not start checkout. ${e.toString()}')),
        );
    }
  }

  Future<bool> _verifyTopupWithRetry(String txRef) async {
    if (txRef.trim().isEmpty) return false;

    Exception? lastError;
    for (var i = 0; i < 4; i++) {
      try {
        final ok = await const _CoinTopupApi().verifyPayChanguTopup(txRef: txRef);
        if (!mounted) return false;
        if (ok) {
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Payment confirmed. Coins added to your wallet.')),
            );
          return true;
        }
      } catch (e) {
        if (e is Exception) {
          lastError = e;
        } else {
          lastError = Exception(e.toString());
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return false;
    final msg = lastError?.toString();
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg == null
                ? 'Payment is still processing. Pull to refresh shortly.'
                : 'Payment is still processing. Pull to refresh shortly. $msg',
          ),
        ),
      );

    return false;
  }

  Future<void> _openWithdraw(UserRole role) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: role,
      capability: CreatorCapability.withdraw,
    );
    if (!allowed || !mounted) return;

    final Widget dest = switch (role) {
      UserRole.dj => const DjEarningsScreen(),
      UserRole.artist => const ArtistEarningsScreen(),
      _ => const SizedBox.shrink(),
    };

    if (dest is SizedBox) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => dest),
    );
  }

  Future<void> _openBuyCoinsSheet(List<_CoinPackage> packages) async {
    if (packages.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No coin packages available right now. Please try again.')),
        );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              Text(
                'Buy coins',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...packages.map((pkg) {
                final total = pkg.coins + pkg.bonusCoins;
                final bonusLabel = pkg.bonusCoins > 0 ? ' (+${pkg.bonusCoins} bonus)' : '';
                final subtitle = '${pkg.currency} ${pkg.price} • $total coins$bonusLabel';
                return ListTile(
                  leading: const Icon(Icons.monetization_on_outlined, color: AppColors.stageGold),
                  title: Text(pkg.title),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_startTopup(pkg));
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSendGiftsFlow() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Open a live and tap the gift icon to send coins.')),
      );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LiveFeedScreen()),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
      ),
    );
  }

  DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _txSubtitle(Map<String, dynamic> t) {
    final created = _parseDate(t['created_at'] ?? t['createdAt']);
    if (created == null) return '';

    final now = DateTime.now();
    final diff = now.difference(created);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final y = created.year.toString().padLeft(4, '0');
    final m = created.month.toString().padLeft(2, '0');
    final d = created.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _amountLabel(Map<String, dynamic> t) {
    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? 0;
    }

    final type = (t['type'] ?? '').toString().trim().toLowerCase();
    final balType = (t['balance_type'] ?? t['balanceType'] ?? '').toString().trim().toLowerCase();
    final amount = asDouble(t['amount']);

    final isCredit = type == 'credit' || type == 'topup' || type == 'deposit' || amount >= 0;
    final sign = isCredit ? '+' : '-';
    final unit = (balType == 'coin' || balType.isEmpty) ? '🪙' : '';

    final fixed = amount.abs().toStringAsFixed(amount.abs() >= 1 ? 0 : 2);
    return '$sign$fixed $unit'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_WalletData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Could not load wallet.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              );
            }

            final data = snap.data;
            if (data == null) {
              return const SizedBox.shrink();
            }

            final coins = data.summary.coinBalance.round();
            final role = data.roleForUi;

            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.stageGold.withValues(alpha: 0.14),
                            border: Border.all(
                              color: AppColors.stageGold.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.monetization_on_outlined,
                            color: AppColors.stageGold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Coins',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$coins',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (role == UserRole.dj || role == UserRole.artist)
                          TextButton.icon(
                            onPressed: () => _openWithdraw(role),
                            icon: const Icon(Icons.account_balance_wallet_outlined),
                            label: const Text('Withdraw'),
                          ),
                      ],
                    ),
                  ),
                ),

                _sectionTitle('Actions'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.shopping_cart_outlined),
                        title: const Text('Buy coins'),
                        subtitle: const Text('Top up your coin balance'),
                        onTap: () => _openBuyCoinsSheet(data.packages),
                      ),
                      ListTile(
                        leading: const Icon(Icons.card_giftcard_outlined),
                        title: const Text('Send gifts'),
                        subtitle: const Text('Support artists & DJs with coin gifts'),
                        onTap: _openSendGiftsFlow,
                      ),
                      ListTile(
                        leading: const Icon(Icons.ondemand_video_outlined),
                        title: const Text('Earn coins'),
                        subtitle: const Text('Watch an ad and earn coins'),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const EarnCoinsScreen()),
                          );
                          if (!mounted) return;
                          await _refresh();
                        },
                      ),
                    ],
                  ),
                ),

                if (data.packages.isNotEmpty) ...[
                  KeyedSubtree(
                    key: _packagesKey,
                    child: _sectionTitle('Buy coins'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: data.packages.map((pkg) {
                        final total = pkg.coins + pkg.bonusCoins;
                        final bonusLabel = pkg.bonusCoins > 0 ? ' (+${pkg.bonusCoins} bonus)' : '';
                        final subtitle = '${pkg.currency} ${pkg.price} • $total coins$bonusLabel';

                        return ListTile(
                          leading: const Icon(Icons.monetization_on_outlined, color: AppColors.stageGold),
                          title: Text(pkg.title),
                          subtitle: Text(subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(_startTopup(pkg)),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ],

                _sectionTitle('Transactions'),
                if (data.transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No transactions yet.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: data.transactions.take(50).map((t) {
                        final desc = (t['description'] ?? '').toString().trim();
                        final type = (t['type'] ?? '').toString().trim();
                        final title = desc.isNotEmpty ? desc : (type.isEmpty ? 'Transaction' : type);
                        final subtitle = _txSubtitle(t);
                        final amount = _amountLabel(t);

                        return ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: subtitle.isEmpty
                              ? null
                              : Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Text(
                            amount,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WalletData {
  const _WalletData({
    required this.roleForUi,
    required this.summary,
    required this.transactions,
    required this.packages,
  });

  final UserRole roleForUi;
  final CreatorWalletSummary summary;
  final List<Map<String, dynamic>> transactions;
  final List<_CoinPackage> packages;
}

class _CoinPackage {
  const _CoinPackage({
    required this.id,
    required this.title,
    required this.coins,
    required this.bonusCoins,
    required this.price,
    required this.currency,
  });

  final String id;
  final String title;
  final int coins;
  final int bonusCoins;
  final num price;
  final String currency;

  static _CoinPackage? tryParse(Map<String, dynamic> json) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    num asNum(Object? v) {
      if (v is num) return v;
      return num.tryParse('${v ?? ''}') ?? 0;
    }

    final id = (json['id'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return null;

    final coins = asInt(json['coins']);
    final bonus = asInt(json['bonus_coins'] ?? json['bonusCoins']);
    final price = asNum(json['price']);
    final currency = (json['currency'] ?? 'MWK').toString().trim().toUpperCase();

    if (coins <= 0 || price <= 0) return null;

    return _CoinPackage(
      id: id,
      title: title,
      coins: coins,
      bonusCoins: bonus < 0 ? 0 : bonus,
      price: price,
      currency: currency.isEmpty ? 'MWK' : currency,
    );
  }
}

class _CoinTopupApi {
  const _CoinTopupApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<List<_CoinPackage>> fetchPackages() async {
    final uri = _uriBuilder.build('/api/coins/packages');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 10),
      includeAuthIfAvailable: false,
      requireAuth: false,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString().trim();
      throw Exception('Coin packages failed (HTTP ${res.statusCode}): $msg');
    }

    final raw = decoded?['packages'];
    if (raw is! List) {
      throw Exception('Coin packages response is missing packages list');
    }

    final out = <_CoinPackage>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.map((k, v) => MapEntry(k.toString(), v));
      final parsed = _CoinPackage.tryParse(m);
      if (parsed != null) out.add(parsed);
    }

    return out;
  }

  Future<_TopupCheckoutSession> startPayChanguCheckout({required String packageId}) async {
    final id = packageId.trim();
    if (id.isEmpty) throw Exception('Missing package id');

    final uri = _uriBuilder.build('/api/coins/paychangu/start');
    final payload = jsonEncode(<String, Object?>{
      'package_id': id,
    });

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: payload,
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString().trim();
      throw Exception('Checkout failed (HTTP ${res.statusCode}): $msg');
    }

    final url = (decoded?['checkout_url'] ?? decoded?['checkoutUrl'] ?? '').toString().trim();
    final checkout = Uri.tryParse(url);
    if (checkout == null) {
      throw Exception('Invalid checkout url');
    }

    final txRef = (decoded?['tx_ref'] ?? decoded?['provider_reference'] ?? '')
        .toString()
        .trim();

    return _TopupCheckoutSession(
      checkoutUrl: checkout,
      txRef: txRef,
    );
  }

  Future<bool> verifyPayChanguTopup({required String txRef}) async {
    final ref = txRef.trim();
    if (ref.isEmpty) return false;

    final uri = _uriBuilder.build('/api/coins/paychangu/verify');
    final payload = jsonEncode(<String, Object?>{
      'tx_ref': ref,
    });

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: payload,
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString().trim();
      throw Exception('Verify failed (HTTP ${res.statusCode}): $msg');
    }

    final success = decoded?['success'];
    return success == true;
  }
}

class _TopupCheckoutSession {
  const _TopupCheckoutSession({
    required this.checkoutUrl,
    required this.txRef,
  });

  final Uri checkoutUrl;
  final String txRef;
}

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver({required this.onResumed});

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
