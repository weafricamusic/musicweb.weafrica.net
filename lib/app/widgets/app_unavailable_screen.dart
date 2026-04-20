import 'package:flutter/material.dart';

import '../config/debug_flags.dart';
import '../theme.dart';

class AppUnavailableScreen extends StatelessWidget {
  const AppUnavailableScreen({
    super.key,
    this.title = 'Service unavailable',
    this.message = 'We’re having trouble starting the app right now. Please try again in a moment.',
    this.details,
  });

  final String title;
  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final showDetails = DebugFlags.showDeveloperUi;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('WeAfrica Music'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textMuted),
          ),
          if (showDetails && details != null && details!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Details',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              details!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
