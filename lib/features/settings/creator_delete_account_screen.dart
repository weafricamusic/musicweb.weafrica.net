import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../artist_dashboard/screens/artist_earnings_screen.dart';
import '../artist_dashboard/services/artist_dashboard_settings_service.dart';
import '../auth/auth_actions.dart';
import '../auth/user_role.dart';
import '../dj_dashboard/screens/dj_earnings_screen.dart';

class CreatorDeleteAccountScreen extends StatefulWidget {
  const CreatorDeleteAccountScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<CreatorDeleteAccountScreen> createState() => _CreatorDeleteAccountScreenState();
}

class _CreatorDeleteAccountScreenState extends State<CreatorDeleteAccountScreen> {
  final _controller = TextEditingController();

  bool _deleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canDelete => _controller.text.trim().toUpperCase() == 'DELETE';

  void _openEarnings() {
    if (widget.role == UserRole.dj) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DjEarningsScreen()));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArtistEarningsScreen()));
  }

  Future<void> _delete() async {
    if (_deleting) return;
    if (!_canDelete) return;

    setState(() => _deleting = true);

    try {
      await const ArtistDashboardSettingsService().deleteAccount();

      // After deletion, sign out locally.
      await AuthActions.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Account deleted.')));
    } catch (e, st) {
      UserFacingError.log('CreatorDeleteAccountScreen._delete', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Delete failed. Please try again.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'This will permanently delete your account.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'If you have pending withdrawals, withdraw first before deleting.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openEarnings,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Open earnings & withdrawals'),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
              hintText: 'DELETE',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _deleting || !_canDelete ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: _deleting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}
