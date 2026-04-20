import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../artist_dashboard/screens/artist_earnings_screen.dart';
import '../auth/auth_actions.dart';
import '../auth/user_role.dart';
import '../auth/user_role_resolver.dart';
import '../dj_dashboard/screens/dj_earnings_screen.dart';
import 'creator_account_settings_screen.dart';
import 'creator_notifications_settings_screen.dart';

class CreatorSettingsScreen extends StatefulWidget {
  const CreatorSettingsScreen({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<CreatorSettingsScreen> createState() => _CreatorSettingsScreenState();
}

class _CreatorSettingsScreenState extends State<CreatorSettingsScreen> {
  UserRole _role = UserRole.consumer;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final r = await UserRoleResolver.resolveCurrentUser();
      if (!mounted) return;
      setState(() {
        _role = r;
        _loadingRole = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _role = UserRole.consumer;
        _loadingRole = false;
      });
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You can sign back in anytime.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await AuthActions.signOut();
    } catch (e, st) {
      UserFacingError.log('CreatorSettingsScreen._confirmLogout', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Logout failed. Please try again.',
              ),
            ),
          ),
        );
    }
  }

  void _openEarnings() {
    if (_role == UserRole.dj) {
      _open(const DjEarningsScreen());
      return;
    }
    _open(const ArtistEarningsScreen());
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool destructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final Color accent = destructive ? cs.error : cs.secondary;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: accent),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: destructive ? accent : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      children: [
        if (!widget.showAppBar) const SizedBox(height: 8),
        _sectionLabel(context, 'Settings'),
        _tile(
          context: context,
          icon: Icons.person_outline,
          title: 'Account',
          subtitle: 'Email, password, profile',
          onTap: () => _open(CreatorAccountSettingsScreen(role: _role)),
        ),
        _tile(
          context: context,
          icon: Icons.account_balance_wallet_outlined,
          title: 'Payment / Withdrawal',
          subtitle: 'Balance, payouts, history',
          onTap: _openEarnings,
        ),
        _tile(
          context: context,
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          subtitle: 'On / off',
          onTap: () => _open(const CreatorNotificationsSettingsScreen()),
        ),
        _sectionLabel(context, 'Account'),
        _tile(
          context: context,
          icon: Icons.logout,
          title: 'Logout',
          destructive: true,
          onTap: _confirmLogout,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: content);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_loadingRole)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: content,
    );
  }
}
