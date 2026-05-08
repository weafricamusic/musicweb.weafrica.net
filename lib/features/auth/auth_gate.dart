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
    print("🔍 AuthGate.build() called");
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print("📊 AuthGate StreamBuilder: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, data=${snapshot.data}");
        
        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
        print("👤 Current user: ${user != null ? 'UID=${user.uid}' : 'null'}");

        if (snapshot.connectionState == ConnectionState.waiting) {
          print("⏳ AuthGate: Showing loading spinner (connectionState=waiting)");
          return const Scaffold(
            backgroundColor: Colors.black, // Ensure dark background
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        if (user == null) {
          print("🔓 AuthGate: No user, showing LoginScreen");
          return const LoginScreen();
        }

        final usesEmailPassword = user.providerData.any(
          (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
        );
        print("📧 User providers: ${user.providerData.map((p) => p.providerId).toList()}");

        // Enforce email verification in release builds.
        // In debug/profile builds we allow sign-in without verification so
        // test accounts (e.g. *.test) can be used without a real inbox.
        if (kReleaseMode && usesEmailPassword && !user.emailVerified) {
          print("📧 AuthGate: Email not verified, showing EmailVerificationScreen");
          return const EmailVerificationScreen();
        }

        print("✅ AuthGate: Showing AppShell");
        // All role-based experiences are in-app (no web dashboards).
        return const AppShell();
      },
    );
  }
}
