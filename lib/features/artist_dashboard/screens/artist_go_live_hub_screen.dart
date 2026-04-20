import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../auth/user_role.dart';
import '../../live/screens/go_live_setup_screen.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';

class ArtistGoLiveHubScreen extends StatefulWidget {
  const ArtistGoLiveHubScreen({super.key});

  @override
  State<ArtistGoLiveHubScreen> createState() => _ArtistGoLiveHubScreenState();
}

class _ArtistGoLiveHubScreenState extends State<ArtistGoLiveHubScreen> {
  bool _battleMode = false;

  String _displayNameForUser(User user) {
    final name = (user.displayName ?? '').trim();
    if (name.isNotEmpty) return name;

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      if (at > 0) return email.substring(0, at);
      return email;
    }

    return 'Artist';
  }

  Future<void> _start(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Please sign in to go live.')));
      return;
    }

    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: UserRole.artist,
      capability: CreatorCapability.goLive,
    );
    if (!allowed || !context.mounted) return;

    final hostName = _displayNameForUser(user);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoLiveSetupScreen(
          role: UserRole.artist,
          hostId: user.uid,
          hostName: hostName,
          initialBattleModeEnabled: _battleMode,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goLiveColor = Theme.of(context).colorScheme.error;
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Go Live',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick a mode and start streaming.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Solo Live')),
              ButtonSegment(value: true, label: Text('Battle Live')),
            ],
            selected: {_battleMode},
            onSelectionChanged: (set) {
              setState(() => _battleMode = set.first);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: goLiveColor,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              onPressed: () => _start(context),
              child: const Text('START LIVE'),
            ),
          ),
        ],
      ),
    );
  }
}
