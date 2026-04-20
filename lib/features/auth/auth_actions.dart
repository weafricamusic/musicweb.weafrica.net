import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/navigation/app_navigator.dart';
import 'user_role_store.dart';

class AuthActions {
  static Future<void> signOut() async {
    try {
      // If the user signed in with Google, signing out of Firebase alone can
      // immediately re-authenticate on some platforms.
      if (!kIsWeb) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (e) {
          debugPrint('GoogleSignIn.signOut failed: $e');
          // Best-effort; still sign out from Firebase.
        }
      }

      await FirebaseAuth.instance.signOut();
      await UserRoleStore.clear();
      AppNavigator.popUntilRoot();
      debugPrint('Successfully signed out');
    } catch (e) {
      debugPrint('FirebaseAuth.signOut failed: $e');
      rethrow;
    }
  }
}
