// lib/features/live/services/battle_invite_listener.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/battle_invite.dart';

class BattleInviteListener {
  static BattleInviteListener? _instance;
  static BattleInviteListener get instance {
    _instance ??= BattleInviteListener._();
    return _instance!;
  }

  BattleInviteListener._();

  RealtimeChannel? _channel;
  bool _isListening = false;
  bool _isStopping = false;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  BuildContext? _lastContext;
  int _reconnectAttempt = 0;
  int _channelGeneration = 0;
  DateTime _lastPollAt = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
  final Set<String> _seenInviteIds = <String>{};
  static const Duration _baseReconnectDelay = Duration(seconds: 3);
  static const Duration _maxReconnectDelay = Duration(seconds: 45);
  String? _listeningUserId;

  void startListening(BuildContext context) {
    _lastContext = context;
    _isStopping = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      debugPrint('No user logged in, cannot listen for battle invites');
      return;
    }

    if (_isListening && _channel != null && _listeningUserId == userId) {
      if (kDebugMode) debugPrint('🔌 BattleInviteListener already listening');
      return;
    }

    if (kDebugMode) debugPrint('🔌 Starting battle invite listener for user: $userId');

    try {
      _isListening = true;
      _listeningUserId = userId;
      _setupListener(context, userId);
      _startPollingFallback(context, userId);
    } catch (e) {
      debugPrint('Error setting up listener: $e');
      _isListening = false;
      _scheduleReconnect();
    }
  }

  void _setupListener(BuildContext context, String userId) {
    _teardownChannel();
    _channelGeneration += 1;
    final generation = _channelGeneration;

    final channel = Supabase.instance.client
        .channel('battle_invites:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'battle_invites',
          callback: (payload) {
            if (_isStopping || generation != _channelGeneration) return;
            final inviteData = payload.newRecord.map((k, v) => MapEntry(k.toString(), v));
            if (inviteData.isEmpty) return;

            final toUid = (inviteData['to_uid'] ?? '').toString().trim();
            if (toUid != userId) return;

            final invite = BattleInvite.fromMap(inviteData);
            _onInviteReceived(context, invite);
          },
        )
        .subscribe((status, error) {
          if (_isStopping || generation != _channelGeneration) {
            return;
          }

          if (error != null) {
            if (kDebugMode) debugPrint('❌ Battle invite subscribe error: $error');
            _isListening = false;
            _scheduleReconnect();
          } else {
            // Reduced spam: only log subscribed (not all statuses)
            if (status == RealtimeSubscribeStatus.subscribed && kDebugMode) debugPrint('✅ Battle invites: SUBSCRIBED');
            if (status == RealtimeSubscribeStatus.subscribed) {
              _isListening = true;
              _reconnectAttempt = 0;
              _reconnectTimer?.cancel();
              _reconnectTimer = null;
            }
          }

          if (status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _isListening = false;
            _scheduleReconnect();
          }
        });

    _channel = channel;
  }

  void _onInviteReceived(BuildContext context, BattleInvite invite) {
    final inviteId = invite.id.trim();
    if (inviteId.isNotEmpty) {
      if (_seenInviteIds.contains(inviteId)) return;
      _seenInviteIds.add(inviteId);
      if (_seenInviteIds.length > 200) {
        _seenInviteIds.remove(_seenInviteIds.first);
      }
    }

    debugPrint('🎯 New battle invite received from: ${invite.fromUid}');
    _showInviteDialog(context, invite.toMap());
  }

  void _startPollingFallback(BuildContext context, String userId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!_isListening || _isStopping || !context.mounted) return;

      try {
        final since = _lastPollAt.toIso8601String();
        final rows = await Supabase.instance.client
            .from('battle_invites')
          .select('id,battle_id,from_uid,to_uid,status,created_at,expires_at,battle_title')
            .eq('to_uid', userId)
            .eq('status', 'pending')
            .gte('created_at', since)
            .order('created_at', ascending: true)
            .limit(20);

        _lastPollAt = DateTime.now().toUtc();

        for (final raw in rows as List<dynamic>) {
          if (raw is! Map) continue;
          final invite = BattleInvite.fromMap(raw.map((k, v) => MapEntry(k.toString(), v)));
          _onInviteReceived(context, invite);
        }
      } catch (e) {
    if (kDebugMode) debugPrint('Battle invite polling fallback skipped: $e');
      }
    });
  }

  void _teardownChannel() {
    if (_channel != null) {
      try {
        _channel?.unsubscribe();
      } catch (_) {
        // ignore
      }
      try {
        Supabase.instance.client.removeChannel(_channel!);
      } catch (_) {
        // ignore
      }
      _channel = null;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    final context = _lastContext;
    if (context == null || !context.mounted) return;

    final multiplier = 1 << (_reconnectAttempt.clamp(0, 4));
    final computedSeconds = _baseReconnectDelay.inSeconds * multiplier;
    final delaySeconds = computedSeconds > _maxReconnectDelay.inSeconds
        ? _maxReconnectDelay.inSeconds
        : computedSeconds;
    final delay = Duration(seconds: delaySeconds);
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 10);

    debugPrint('Battle invite listener reconnect in ${delay.inSeconds}s (attempt=$_reconnectAttempt)');

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isListening && context.mounted) {
    if (kDebugMode) debugPrint('Retrying battle invite listener subscription...');
        startListening(context);
      }
    });
  }

  void _showInviteDialog(BuildContext context, Map<String, dynamic> inviteData) {
    if (!context.mounted) {
      debugPrint('Context not mounted, cannot show dialog');
      return;
    }

    // Extract data safely
    final fromUserName = inviteData['from_user_name']?.toString() ?? 'Someone';
    final battleTitle = inviteData['battle_title']?.toString() ?? 'Battle Challenge';
    final battleId = inviteData['battle_id']?.toString() ?? '';
    final inviteId = inviteData['id']?.toString() ?? '';
    final fromUserId = inviteData['from_uid']?.toString() ?? '';

    debugPrint('Showing invite dialog from: $fromUserName');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0E2414),
        title: const Row(
          children: [
            Icon(Icons.sports_mma, color: Color(0xFF2F9B57)),
            SizedBox(width: 8),
            Text('Battle Challenge!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You have been challenged to a battle!',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF2F9B57).withValues(alpha: 0.2), const Color(0xFF0E2414)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2F9B57), width: 1),
              ),
              child: Column(
                children: [
                  const Icon(Icons.emoji_events, color: Color(0xFF2F9B57), size: 32),
                  const SizedBox(height: 8),
                  Text(
                    battleTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From: $fromUserName',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _declineInvite(inviteId, dialogContext, context),
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F9B57),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _acceptInvite(battleId, inviteId, fromUserId, fromUserName, dialogContext, context),
            child: const Text('Accept Battle!'),
          ),
        ],
      ),
    );
  }

  void _acceptInvite(String battleId, String inviteId, String fromUserId, String fromUserName, BuildContext dialogContext, BuildContext scaffoldContext) {
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }

    debugPrint('Accepting battle invite: $inviteId');

    if (scaffoldContext.mounted) {
      // Navigate to battle lobby
      Navigator.pushNamed(
        scaffoldContext,
        '/battle/lobby',
        arguments: {
          'battleId': battleId,
          'inviteId': inviteId,
          'fromUserId': fromUserId,
          'fromUserName': fromUserName,
        },
      );
    }
  }

  void _declineInvite(String inviteId, BuildContext dialogContext, BuildContext scaffoldContext) {
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }

    debugPrint('Declining battle invite: $inviteId');

    if (scaffoldContext.mounted) {
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        const SnackBar(content: Text('Battle declined'), backgroundColor: Colors.orange),
      );
    }
  }

  void stopListening() {
    _isStopping = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastContext = null;
    _listeningUserId = null;
    _reconnectAttempt = 0;
    _channelGeneration += 1;

  if (kDebugMode) debugPrint('🔌 Stopping battle invite listener');
    _teardownChannel();

    _isListening = false;
  }
}
