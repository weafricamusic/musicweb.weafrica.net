import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class FacebookAuthService {
  static Future<UserCredential?> signInWithFacebook() async {
    final result = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    if (result.status == LoginStatus.success) {
      final token = result.accessToken!;
      final credential = FacebookAuthProvider.credential(token.tokenString);
      return FirebaseAuth.instance.signInWithCredential(credential);
    }

    debugPrint('Facebook login failed: ${result.message}');
    return null;
  }
}
