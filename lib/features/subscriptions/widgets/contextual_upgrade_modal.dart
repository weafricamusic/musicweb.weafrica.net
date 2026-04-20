import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../auth/login_screen.dart';
import '../models/subscription_plan.dart';
import '../services/paychangu_checkout_loader.dart';
import '../services/upgrade_flow_manager.dart';
import '../subscription_color_hierarchy.dart';
import 'upgrade_prompt_factory.dart';

Future<bool> showContextualUpgradeModal(
  BuildContext context, {
  required UpgradePrompt prompt,
  String source = 'unknown',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ContextualUpgradeModal(prompt: prompt, source: source),
  );

  return result == true;
}

class _ContextualUpgradeModal extends StatefulWidget {
  const _ContextualUpgradeModal({
    required this.prompt,
    required this.source,
  });

  final UpgradePrompt prompt;
  final String source;

  @override
  State<_ContextualUpgradeModal> createState() => _ContextualUpgradeModalState();
}

class _ContextualUpgradeModalState extends State<_ContextualUpgradeModal> {
  final _manager = UpgradeFlowManager.instance;
  final _loader = PayChanguCheckoutLoader.instance;

  SubscriptionPlan? _plan;
  Uri? _preloadedUrl;
  String _preloadedTxRef = '';
  Object? _preloadError;
  bool _loading = true;
  bool _ctaBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_preload());
  }

  bool get _signedIn => FirebaseAuth.instance.currentUser != null;

  Future<void> _preload() async {
    setState(() {
      _loading = true;
      _preloadError = null;
    });

    try {
      final plan = await _manager.resolvePlan(
        planId: widget.prompt.recommendedPlanId(),
        role: widget.prompt.role,
      );

      Uri? url;
      String txRef = '';
      if (_signedIn) {
        final session = await _loader.preloadSession(plan: plan);
        url = session.checkoutUrl;
        txRef = session.txRef;
      }

      if (!mounted) return;
      setState(() {
        _plan = plan;
        _preloadedUrl = url;
        _preloadedTxRef = txRef;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preloadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _onPrimaryCta() async {
    if (_ctaBusy) return;

    if (!_signedIn) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );

      if (!mounted) return;
      // After returning from login, preload checkout.
      unawaited(_preload());
      return;
    }

    final plan = _plan;
    if (plan == null) {
      unawaited(_preload());
      return;
    }

    setState(() => _ctaBusy = true);

    final result = await _manager.upgradePlan(
      context: context,
      plan: plan,
      preloadedCheckoutUrl: _preloadedUrl,
      preloadedTxRef: _preloadedTxRef,
      source: widget.source,
    );

    if (!mounted) return;
    setState(() => _ctaBusy = false);

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = subscriptionTierAccent(widget.prompt.subscriptionTier, scheme);

    final planName = widget.prompt.recommendedPlanDisplayName();
    final primaryLabel = _signedIn
        ? 'Upgrade to $planName'
        : 'Sign in to upgrade';

    final helperText = _signedIn
        ? 'Secure checkout via PayChangu'
        : 'Sign in to continue with secure checkout';

    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(widget.prompt.icon, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.prompt.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.prompt.message,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.prompt.nearLimitLabel != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: WeAfricaColors.goldLight.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: WeAfricaColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.prompt.nearLimitLabel!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...widget.prompt.benefit.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 18, color: WeAfricaColors.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text(b, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
            if (_preloadError != null) ...[
              const SizedBox(height: 8),
              Text(
                'We couldn\'t prepare checkout. Check your connection and try again.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton(
              onPressed: (_loading || _ctaBusy) ? null : _onPrimaryCta,
              child: _ctaBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel),
            ),
            const SizedBox(height: 8),
            Text(
              helperText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 6),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _ctaBusy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
