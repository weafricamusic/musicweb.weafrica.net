// lib/services/battle_invite_manager.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:weafrica_music/features/live/services/battle_invite_listener.dart';

class BattleInviteManager {
  bool _isListening = false;
  String? _listeningUserId;
  BuildContext? _context;
  StreamSubscription<User?>? _authSubscription;

  void initialize(BuildContext context) {
    _context = context;
    _authSubscription?.cancel();
    
    // Listen for auth state changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null && _context != null && _context!.mounted) {
        if (_isListening && _listeningUserId == user.uid) {
          return;
        }
        debugPrint('User logged in: ${user.uid}, starting battle invite listener');
        BattleInviteListener.instance.startListening(_context!);
        _isListening = true;
        _listeningUserId = user.uid;
      } else if (user == null && _isListening) {
        debugPrint('User logged out, stopping battle invite listener');
        BattleInviteListener.instance.stopListening();
        _isListening = false;
        _listeningUserId = null;
      }
    });
    
    // Also check current user immediately
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && _context != null && _context!.mounted) {
      if (_isListening && _listeningUserId == currentUser.uid) {
        return;
      }
      debugPrint('Current user: ${currentUser.uid}, starting battle invite listener');
      BattleInviteListener.instance.startListening(_context!);
      _isListening = true;
      _listeningUserId = currentUser.uid;
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    if (_isListening) {
      BattleInviteListener.instance.stopListening();
      _isListening = false;
      _listeningUserId = null;
    }
    _context = null;
  }
}
