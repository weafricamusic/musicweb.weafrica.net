import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../battle/widgets/battle_invite_dialog.dart';

/// Listens for incoming battle invites in real-time.
class BattleInviteListener {
  static final BattleInviteListener _instance = BattleInviteListener._internal();
  static BattleInviteListener get instance => _instance;
  BattleInviteListener._internal();

  RealtimeChannel? _channel;
  bool _isListening = false;
  String? _currentUid;

  void startListening(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    if (_isListening && _currentUid == uid) return;

    if (_isListening) {
      stopListening();
    }

    _currentUid = uid;

    try {
      _channel = Supabase.instance.client
          .channel('battle_invites:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'battle_invites',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'to_uid',
              value: uid,
            ),
            callback: (payload) {
              debugPrint('Battle invite received: ${payload.newRecord}');
              if (context.mounted) {
                BattleInviteDialog.show(context, payload.newRecord);
              }
            },
          )
          .subscribe((status, [error]) {
            debugPrint('Battle invite listener status: $status');
            if (status.name == 'subscribed') {
              _isListening = true;
            }
          });
    } catch (e) {
      debugPrint('Failed to start battle invite listener: $e');
    }
  }

  void stopListening() {
    if (!_isListening) return;
    _channel?.unsubscribe();
    _channel = null;
    _isListening = false;
    _currentUid = null;
  }
}
