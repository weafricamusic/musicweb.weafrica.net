import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import 'artist_stats_screen.dart';

class ArtistLiveManagerScreen extends StatelessWidget {
  const ArtistLiveManagerScreen({super.key});

  static const String _notifyPrefKey = 'weafrica_live_notify_when_ready';

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _saveNotifyMe(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyPrefKey, true);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Noted. We’ll notify you when Live is ready.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Manager'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Creator Tools',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.brandOrange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Live is currently being rebuilt.\nYou can still review analytics.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _CreatorToolCard(
                  title: 'Live analytics',
                  subtitle: 'View your performance and viewer stats',
                  icon: Icons.analytics_outlined,
                  ctaLabel: 'VIEW ANALYTICS →',
                  onPressed: () => _open(context, const ArtistStatsScreen()),
                ),
                const SizedBox(height: 12),
                _CreatorToolCard(
                  title: 'Live (rebuilding)',
                  subtitle: 'We’ll ship the new Live soon',
                  icon: Icons.wifi_tethering,
                  ctaLabel: 'NOTIFY ME WHEN READY',
                  onPressed: () => _saveNotifyMe(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorToolCard extends StatelessWidget {
  const _CreatorToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.ctaLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String ctaLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.textMuted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: onPressed,
                    child: Text(ctaLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
