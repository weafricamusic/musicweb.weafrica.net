import 'package:flutter/material.dart';
import '../auth/user_role.dart';
import 'consumer_settings_screen.dart';

class RoleBasedSettingsScreen extends StatelessWidget {
  const RoleBasedSettingsScreen({super.key, this.roleOverride});

  final UserRole? roleOverride;

  @override
  Widget build(BuildContext context) {
    // Only Consumer users access settings from the main app
    // Artists and DJs manage their settings through the Studio Dashboard
    return const ConsumerSettingsScreen();
  }
}