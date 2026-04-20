import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjBoostsScreen extends StatefulWidget {
  const DjBoostsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjBoostsScreen> createState() => _DjBoostsScreenState();
}

class _DjBoostsScreenState extends State<DjBoostsScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<List<DjBoost>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DjBoost>> _load() async {
    final uid = _identity.requireDjUid();
    return _service.listBoosts(djUid: uid);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<DjBoost>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Could not load boosts. Please try again.',
            onRetry: () => setState(() { _future = _load(); }),
          );
        }

        final boosts = snapshot.data ?? [];

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text(
              'Active Boosts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (boosts.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text('No active boosts'),
              )
            else
              ...boosts.map((boost) => _BoostTile(boost)),

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showCreateBoostDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create New Boost'),
            ),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('DJ Boosts')),
      body: body,
    );
  }

  void _showCreateBoostDialog(BuildContext context) {
    final amountCtrl = TextEditingController(text: '5');
    final contentIdCtrl = TextEditingController();
    String contentType = 'set';
    var busy = false;
    String? error;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              if (busy) return;
              setState(() {
                busy = true;
                error = null;
              });
              try {
                final uid = _identity.requireDjUid();
                final amount = num.tryParse(amountCtrl.text.trim()) ?? 0;
                final contentId = contentIdCtrl.text.trim();
                if (amount <= 0) {
                  throw Exception('Enter a boost amount greater than 0.');
                }
                if (contentId.isEmpty) {
                  throw Exception('Enter a content ID (set id or live channel id).');
                }

                await _service.createBoost(
                  djUid: uid,
                  contentType: contentType,
                  contentId: contentId,
                  amount: amount,
                );

                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (!mounted) return;
                setState(() { _future = _load(); });
              } catch (e, st) {
                UserFacingError.log('DjBoostsScreen.createBoost', e, st);
                if (!ctx.mounted) return;
                setState(() {
                  error = UserFacingError.message(
                    e,
                    fallback: 'Could not create boost. Please try again.',
                  );
                });
              } finally {
                if (ctx.mounted) setState(() { busy = false; });
              }
            }

            return AlertDialog(
              title: const Text('Create Boost'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(contentType),
                      initialValue: contentType,
                      decoration: const InputDecoration(labelText: 'Content type'),
                      items: const [
                        DropdownMenuItem(value: 'set', child: Text('Set / mix')),
                        DropdownMenuItem(value: 'live', child: Text('Live session')),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() { contentType = v; });
                            },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentIdCtrl,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Content ID',
                        hintText: 'Paste set id or live channel id',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(color: AppColors.brandBlue),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
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
    ).whenComplete(() {
      amountCtrl.dispose();
      contentIdCtrl.dispose();
    });
  }
}

class _BoostTile extends StatelessWidget {
  const _BoostTile(this.boost);

  final DjBoost boost;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Boost for ${boost.contentType ?? 'content'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                boost.status,
                style: TextStyle(
                  color: boost.status == 'active' ? Colors.green : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\$${boost.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            boost.createdAt.toLocal().toString().split('.').first,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}