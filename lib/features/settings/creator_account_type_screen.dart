import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../auth/user_role.dart';
import '../auth/user_role_intent_store.dart';

class CreatorAccountTypeScreen extends StatefulWidget {
  const CreatorAccountTypeScreen({super.key, required this.resolvedRole});

  final UserRole resolvedRole;

  @override
  State<CreatorAccountTypeScreen> createState() => _CreatorAccountTypeScreenState();
}

class _CreatorAccountTypeScreenState extends State<CreatorAccountTypeScreen> {
  bool _loading = true;
  UserRole _selected = UserRole.consumer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await UserRoleIntentStore.getRole();
    if (!mounted) return;
    setState(() {
      _selected = current;
      _loading = false;
    });
  }

  String _modeLabel(UserRole role) {
    switch (role) {
      case UserRole.consumer:
        return 'Listener';
      case UserRole.artist:
        return 'Artist';
      case UserRole.dj:
        return 'DJ';
    }
  }

  String _modeSubtitle(UserRole role) {
    switch (role) {
      case UserRole.consumer:
        return 'Browse music with the listener tabs';
      case UserRole.artist:
        return 'Show Studio and creator tools';
      case UserRole.dj:
        return 'Show Studio and DJ tools';
    }
  }

  List<UserRole> get _options {
    final out = <UserRole>[UserRole.consumer];

    // Only allow switching into roles this account actually has.
    // (Creators can always switch back to Listener mode.)
    if (widget.resolvedRole == UserRole.artist) {
      out.add(UserRole.artist);
    } else if (widget.resolvedRole == UserRole.dj) {
      out.add(UserRole.dj);
    }

    return out;
  }

  void _setRole(UserRole next) {
    setState(() => _selected = next);

    () async {
      try {
        await UserRoleIntentStore.setRole(next);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Switched to ${_modeLabel(next)} mode.')),
          );
      } catch (e, st) {
        UserFacingError.log('CreatorAccountTypeScreen._setRole', e, st);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.message(
                  e,
                  fallback: 'Could not switch mode. Please try again.',
                ),
              ),
            ),
          );
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account type')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RadioGroup<UserRole>(
              groupValue: _selected,
              onChanged: (v) {
                if (v == null) return;
                _setRole(v);
              },
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Switch mode',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'This changes your bottom navigation (Listener vs Studio).',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  ..._options.map(
                    (role) => RadioListTile<UserRole>(
                      value: role,
                      title: Text(_modeLabel(role), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_modeSubtitle(role), style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
