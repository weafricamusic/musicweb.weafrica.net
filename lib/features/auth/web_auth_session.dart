import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'creator_profile_provisioner.dart';
import 'user_profile_provisioner.dart';
import 'user_role_intent_store.dart';

class WebAuthSession {
  WebAuthSession._();

  static bool _persistenceConfigured = false;
  static bool _redirectHandled = false;

  static Future<void> initialize() async {
    if (!kIsWeb) return;

    await ensurePersistence();

    if (_redirectHandled) return;
    _redirectHandled = true;

    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null) {
        await _runPostSignInProvisioning();
      }
    } catch (e, st) {
      developer.log(
        'Completing the pending web auth redirect failed.',
        name: 'WEAFRICA.Auth',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> ensurePersistence() async {
    if (!kIsWeb || _persistenceConfigured) return;

    final auth = FirebaseAuth.instance;
    const persistenceOrder = <Persistence>[
      Persistence.LOCAL,
      Persistence.INDEXED_DB,
      Persistence.SESSION,
      Persistence.NONE,
    ];

    for (final persistence in persistenceOrder) {
      try {
        await auth.setPersistence(persistence);
        _persistenceConfigured = true;
        return;
      } catch (e, st) {
        developer.log(
          'Web auth persistence ${persistence.name} is unavailable. Trying the next option.',
          name: 'WEAFRICA.Auth',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  static Future<void> _runPostSignInProvisioning() async {
    final intent = await UserRoleIntentStore.getRole();
    await UserProfileProvisioner.ensureForCurrentUser(intent: intent);
    await CreatorProfileProvisioner.ensureForCurrentUser(intent: intent);
  }
}