import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/weafrica_colors.dart';

/// Friendly UI-level error boundary.
///
/// This doesn't expose backend details; it renders a simple fallback when a
/// subtree throws during build.
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackMessage = 'Something went wrong.',
    this.onReset,
  });

  final Widget child;
  final String fallbackMessage;
  final VoidCallback? onReset;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    ErrorWidget.builder = (details) {
      _error = details.exception;
      return _Fallback(message: widget.fallbackMessage, onReset: _reset);
    };
  }

  void _reset() {
    setState(() => _error = null);
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _Fallback(message: widget.fallbackMessage, onReset: _reset);
    }
    return widget.child;
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.message, required this.onReset});

  final String message;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.theater_comedy, color: WeAfricaColors.gold, size: 56),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onReset,
                child: const Text('Retry', style: TextStyle(color: WeAfricaColors.gold)),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 10),
                const Text('Debug mode: check logs for details.', style: TextStyle(color: Colors.white38)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
