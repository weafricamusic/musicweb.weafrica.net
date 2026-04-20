import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../shell/app_shell.dart';
import 'login_screen.dart';
import 'email_verification_screen.dart';
import '../../services/battle_invite_manager.dart'; // ADD THIS

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.battleInviteManager}); // MODIFY THIS

  final BattleInviteManager? battleInviteManager; // ADD THIS

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Initialize battle invite listener after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.battleInviteManager != null) {
        widget.battleInviteManager!.initialize(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (user == null) {
          return const LoginScreen();
        }

        final usesEmailPassword = user.providerData.any(
          (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
        );

        // Enforce email verification in release builds.
        // In debug/profile builds we allow sign-in without verification so
        // test accounts (e.g. *.test) can be used without a real inbox.
        if (kReleaseMode && usesEmailPassword && !user.emailVerified) {
          return const EmailVerificationScreen();
        }

        // All role-based experiences are in-app (no web dashboards).
        return const AppShell();
      },
    );
  }
}
