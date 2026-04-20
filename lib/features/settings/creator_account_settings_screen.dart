import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../artist_dashboard/screens/artist_profile_settings_screen.dart';
import '../auth/user_role.dart';
import '../dj_dashboard/screens/dj_profile_screen.dart';
import '../profile/edit_profile_screen.dart';

class CreatorAccountSettingsScreen extends StatelessWidget {
  const CreatorAccountSettingsScreen({super.key, required this.role});

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
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          _tile(
            context: context,
            icon: Icons.badge_outlined,
            title: 'Profile info',
            subtitle: 'Edit your creator profile',
            onTap: () {
              if (role == UserRole.artist) {
                _open(context, const ArtistProfileSettingsScreen());
              } else if (role == UserRole.dj) {
                _open(context, const DjProfileScreen());
              } else {
                _open(context, const EditProfileScreen());
              }
            },
          ),
          _tile(
            context: context,
            icon: Icons.email_outlined,
            title: 'Email & phone',
            subtitle: 'View your contact details',
            onTap: () {
              ScaffoldMessenger.of(context)
                ..removeCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Contact details are managed by your sign-in provider.'),
                  ),
                );
            },
          ),
          _tile(
            context: context,
            icon: Icons.account_balance_outlined,
            title: 'Payout details',
            subtitle: 'Manage your withdrawal method',
            onTap: () {
              ScaffoldMessenger.of(context)
                ..removeCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Open Earnings to manage payouts.')));
            },
          ),
        ],
      ),
    );
  }
}
