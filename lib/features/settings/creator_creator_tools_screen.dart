import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../auth/user_role.dart';
import '../dj_dashboard/screens/dj_stats_screen.dart';
import '../upload/screens/creator_upload_screen.dart';
import '../artist/dashboard/screens/artist_stats_screen.dart';

class CreatorCreatorToolsScreen extends StatelessWidget {
  const CreatorCreatorToolsScreen({super.key, required this.role});

  final UserRole role;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Creator tools')),
      body: ListView(
        children: [
          _tile(
            context: context,
            icon: Icons.cloud_upload_outlined,
            title: 'Upload content',
            subtitle: 'Tracks & videos',
            onTap: () => _open(context, CreatorUploadScreen(creatorIntent: role)),
          ),
          _tile(
            context: context,
            icon: Icons.insights_outlined,
            title: 'Analytics',
            subtitle: 'Plays, top songs, performance',
            onTap: () {
              if (role == UserRole.dj) {
                _open(context, const DjStatsScreen(showAppBar: true));
                return;
              }
              if (role == UserRole.artist) {
                _open(context, const ArtistStatsScreen());
                return;
              }
              ScaffoldMessenger.of(context)
                ..removeCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Creator analytics are available for Artist/DJ accounts.')));
            },
          ),
        ],
      ),
    );
  }
}
