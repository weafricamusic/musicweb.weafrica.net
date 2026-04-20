import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum CheckoutOutcome { completed, canceled }

/// In-app PayChangu checkout.
///
/// This keeps users inside the app rather than switching to an external browser.
///
class CheckoutWebviewScreen extends StatefulWidget {
  const CheckoutWebviewScreen({
    super.key,
    required this.initialUrl,
    this.expectedPlanId,
  });

  final Uri initialUrl;
  final String? expectedPlanId;

  @override
  State<CheckoutWebviewScreen> createState() => _CheckoutWebviewScreenState();
}

class _CheckoutWebviewScreenState extends State<CheckoutWebviewScreen> {
  late final WebViewController _controller;
  String _lastUrl = '';
  bool _loading = true;
  String? _error;
  Timer? _stuckTimer;

  bool _isAllowedInAppScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'data';
  }

  CheckoutOutcome? _outcomeFromReturnUrl(String url) {
    final lower = url.toLowerCase();

    // Supabase Edge Function uses these:
    // - /api/paychangu/callback (success)
    // - /api/paychangu/return (not completed / canceled)
    if (lower.contains('/api/paychangu/return')) return CheckoutOutcome.canceled;
    if (lower.contains('/api/paychangu/callback')) return CheckoutOutcome.completed;

    // Generic PayChangu patterns (best-effort): infer from query params.
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final status = (uri.queryParameters['status'] ?? '').trim().toLowerCase();
    if (status == 'success' || status == 'successful' || status == 'completed') {
      return CheckoutOutcome.completed;
    }
    if (status == 'cancelled' || status == 'canceled' || status == 'failed' || status == 'error') {
      return CheckoutOutcome.canceled;
    }

    // If it looks like a terminal redirect but status is unknown,
    // treat it as completed so the app can refresh state.
    final hasTxRef = uri.queryParameters.containsKey('tx_ref') || uri.queryParameters.containsKey('transaction_id');
    if (hasTxRef) return CheckoutOutcome.completed;

    return null;
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _lastUrl = url;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _loading = false;
              _lastUrl = url;
            });
          },
          onWebResourceError: (err) {
            // Keep the page visible if possible, but surface a friendly banner.
            setState(() {
              _error = '${err.errorCode}: ${err.description}';
              _loading = false;
            });
          },
          onNavigationRequest: (request) {
            _lastUrl = request.url;

            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }

            // Keep checkout inside the app: block deep-link/app-intent schemes
            // that may switch users to external apps or browsers.
            if (!_isAllowedInAppScheme(uri)) {
              setState(() {
                _loading = false;
                _error = 'This payment step tried to open another app. Please use in-page checkout options to stay in WeAfrica.';
              });
              return NavigationDecision.prevent;
            }

            // If the checkout redirects back to our backend callback/return pages,
            // allow the navigation but auto-close shortly after so the app can
            // refresh state.
            final outcome = _outcomeFromReturnUrl(request.url);
            if (outcome != null) {
              _scheduleAutoClose(outcome);
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.initialUrl);

    // Safety: if something gets stuck on a blank page, encourage browser fallback.
    _stuckTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted) return;
      if (_loading) {
        setState(() {
          _error ??= 'Checkout is taking longer than expected. Please stay on this screen while we keep it in-app.';
        });
      }
    });
  }

  @override
  void dispose() {
    _stuckTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoClose(CheckoutOutcome outcome) {
    // Close after a short delay so the user can see a confirmation page.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(CheckoutOutcome.canceled);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure checkout'),
          actions: [
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(CheckoutOutcome.canceled),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Material(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (kDebugMode && _lastUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _lastUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
