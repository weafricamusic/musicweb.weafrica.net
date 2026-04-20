import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'about_weafrica_music_page.dart';
import 'rate_app.dart';

class CreatorSupportAboutScreen extends StatelessWidget {
  const CreatorSupportAboutScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Theme.of(context).colorScheme.secondary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        children: [
          _tile(
            context: context,
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'App version and info',
            onTap: () => _open(context, const AboutWeAfricaMusicPage()),
          ),
          _tile(
            context: context,
            icon: Icons.star_rate_outlined,
            title: 'Rate app',
            subtitle: 'Leave a review',
            onTap: () async {
              final ok = await rateApp();
              if (!context.mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context)
                  ..removeCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Could not open the review page.')));
              }
            },
          ),
        ],
      );

    if (!showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Support & about')),
      body: body,
    );
  }
}
