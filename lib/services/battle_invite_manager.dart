import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../features/live_old/services/battle_invite_listener.dart';
import '../features/live_old/services/battle_invite_service.dart';

export '../features/live_old/models/battle_invite.dart' show BattleInvite;

/// Manages battle invites with a singleton pattern for global access
class BattleInviteManager {
  static final BattleInviteManager _instance = BattleInviteManager._internal();
  factory BattleInviteManager() => _instance;
  BattleInviteManager._internal();

  final BattleInviteService _service = BattleInviteService();

  BuildContext? _context;

  void initialize(BuildContext context) {
    _context = context;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      BattleInviteListener.instance.startListening(context);
    }
  }

  void dispose() {
    BattleInviteListener.instance.stopListening();
    _context = null;
  }

  Future<void> respondToInvite({
    required String inviteId,
    required String action,
  }) async {
    await _service.respondToInvite(
      inviteId: inviteId,
      accept: action == 'accept',
    );
  }
}