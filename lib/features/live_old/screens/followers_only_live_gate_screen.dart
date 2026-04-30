import 'package:flutter/material.dart';

import '../../../app/theme/weafrica_colors.dart';

class FollowersOnlyLiveGateScreen extends StatelessWidget {
  const FollowersOnlyLiveGateScreen({
    super.key,
    required this.hostName,
    required this.onFollowJoin,
    required this.onBack,
    this.isLoading = false,
    this.message,
  });

  final String hostName;
  final VoidCallback onFollowJoin;
  final VoidCallback onBack;
  final bool isLoading;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final safeHost = hostName.trim().isEmpty ? 'this creator' : hostName.trim();
    final body = (message ?? '').trim().isEmpty
        ? 'This live is for followers only. Follow $safeHost to join now.'
        : message!.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: WeAfricaColors.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    size: 38,
                    color: WeAfricaColors.gold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Followers Only Live',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : onFollowJoin,
                    child: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Follow + Join'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: isLoading ? null : onBack,
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
