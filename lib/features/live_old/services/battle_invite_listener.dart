import "../live_screen.dart";
import "../models/live_args.dart";
import "../../auth/user_role.dart";
// lib/features/live/services/battle_invite_listener.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';

import 'battle_matching_api.dart';

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
  final Set<String> _seenInviteIds = <String>{};
  static const Duration _baseReconnectDelay = Duration(seconds: 3);
  static const Duration _maxReconnectDelay = Duration(seconds: 45);
  String? _listeningUserId;
  AudioPlayer? _ringtonePlayer;

  void startListening(BuildContext context) {
    _lastContext = context;
    _isStopping = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final userId = FirebaseAuth.instance.currentUser?.uid?.trim();
    if (userId == null || userId.isEmpty) {
      debugPrint('No user logged in, cannot listen for battle invites');
      return;
    }

    if (_isListening && _channel != null && _listeningUserId == userId) {
      if (kDebugMode) debugPrint('🔌 BattleInviteListener already listening');
      return;
    }

    if (kDebugMode)
      debugPrint('🔌 Starting battle invite listener for user: $userId');

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

            final inviteData = payload.newRecord.map(
              (k, v) => MapEntry(k.toString(), v),
            );
            if (inviteData.isEmpty) return;

            final toUid = (inviteData['to_uid'] ?? '').toString().trim();
            final status = (inviteData['status'] ?? '').toString().trim();

            if (toUid != userId || status != 'pending') return;

            final invite = BattleInvite.fromMap(inviteData);
            _onInviteReceived(context, invite);
          },
        )
        .subscribe((status, error) {
          if (_isStopping || generation != _channelGeneration) return;

          if (error != null) {
            if (kDebugMode)
              debugPrint('❌ Battle invite subscribe error: $error');
            _isListening = false;
            _scheduleReconnect();
            return;
          }

          if (status == RealtimeSubscribeStatus.subscribed) {
            if (kDebugMode) debugPrint('✅ Battle invites: SUBSCRIBED');
            _isListening = true;
            _reconnectAttempt = 0;
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
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

  Future<void> _playRingtone() async {
    try {
      await _ringtonePlayer?.stop();
      await _ringtonePlayer?.dispose();

      _ringtonePlayer = AudioPlayer();
      await _ringtonePlayer?.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer?.setVolume(1.0);
      await _ringtonePlayer?.play(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      debugPrint('Failed to play ringtone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer?.stop();
      await _ringtonePlayer?.dispose();
      _ringtonePlayer = null;
    } catch (_) {}
  }

  void _showInviteDialog(
    BuildContext context,
    Map<String, dynamic> inviteData,
  ) {
    if (!context.mounted) {
      debugPrint('Context not mounted, cannot show dialog');
      return;
    }

    unawaited(_playRingtone());

    final fromUserId = inviteData['from_uid']?.toString() ?? '';
    final fromUserName = inviteData['from_user_name']?.toString() ?? 'Someone';
    final battleId = inviteData['battle_id']?.toString() ?? '';
    final battleTitle =
        inviteData['battle_title']?.toString() ?? 'Battle Challenge';

    debugPrint('🔔 Showing invite dialog from: $fromUserName with ringtone');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async {
          await _stopRingtone();
          return true;
        },
        child: AlertDialog(
          backgroundColor: const Color(0xFF0E2414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk, color: Color(0xFF2F9B57)),
              SizedBox(width: 8),
              Text(
                'INCOMING BATTLE!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports_mma, size: 50, color: Color(0xFF2F9B57)),
              const SizedBox(height: 16),
              Text(
                '$fromUserName is challenging you',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2F9B57)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  battleTitle,
                  style: const TextStyle(
                    color: Color(0xFF2F9B57),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volume_up, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text('Ringing...', style: TextStyle(color: Colors.green)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                unawaited(_stopRingtone());
                Navigator.of(dialogContext).pop();
                unawaited(_declineInvite(
                  inviteData['id']?.toString() ?? '',
                  dialogContext,
                  context,
                ));
              },
              child: const Text('DECLINE', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F9B57),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                unawaited(_stopRingtone());
                Navigator.of(dialogContext).pop();
                unawaited(_acceptInvite(
                  battleId,
                  inviteData['id']?.toString() ?? '',
                  fromUserId,
                  fromUserName,
                  dialogContext,
                  context,
                ));
              },
              child: const Text('ACCEPT'),
            ),
          ],
        ),
      ),
    ).then((_) => unawaited(_stopRingtone()));
  }

  Future<void> _acceptInvite(
    String battleId,
    String inviteId,
    String fromUserId,
    String fromUserName,
    BuildContext dialogContext,
    BuildContext scaffoldContext,
  ) async {
    debugPrint('Accepting battle invite: $inviteId');

    if (!scaffoldContext.mounted) return;

    // Show loading indicator
    showDialog(
      context: scaffoldContext,
      barrierDismissible: false,
      builder: (loadingCtx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2F9B57)),
      ),
    );

    try {
      // Call API to accept the invite
      final battle = await const BattleMatchingApi().respondToInvite(
        inviteId: inviteId,
        action: 'accept',
      );

      // Close loading dialog
      if (scaffoldContext.mounted) {
        Navigator.of(scaffoldContext).pop(); // Close loading
      }

      if (!scaffoldContext.mounted) return;

      // Get current user info
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid?.trim() ?? '';
      if (uid.isEmpty) {
        debugPrint('No user logged in, cannot join battle');
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(content: Text('Please log in to join the battle.')),
        );
        return;
      }

      // Resolve user role
      UserRole role = UserRole.artist;
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', uid)
            .maybeSingle();
        final roleId = (row?['role'] ?? '').toString().toLowerCase();
        role = UserRoleX.fromId(roleId);
        if (role == UserRole.consumer) role = UserRole.artist;
      } catch (_) {
        // Default to artist
      }

      final displayName = user?.displayName?.trim();
      final userName = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : role.label;

      // Build participants list
      final participants = <String>{
        fromUserId,
        uid,
        battle.hostAId?.trim() ?? '',
        battle.hostBId?.trim() ?? '',
      }.where((value) => value.isNotEmpty).toList(growable: false);

      // IMPORTANT: The hostId should be the battle creator (hostAId), NOT the invitee
      // This ensures the invited artist joins as audience, not as broadcaster
      final battleHostId = battle.hostAId?.trim().isNotEmpty == true
          ? battle.hostAId!
          : fromUserId;

      debugPrint('Battle invite accepted: hostAId=${battle.hostAId}, hostBId=${battle.hostBId}, setting hostId=$battleHostId');

      // Navigate to live battle screen
      Navigator.of(scaffoldContext).push(
        MaterialPageRoute(
          builder: (_) => LiveScreen(
            args: LiveArgs(
              liveId: battle.channelId,
              channelId: battle.channelId,
              role: role,
              hostId: battleHostId,  // Use actual battle host, not invitee
              hostName: fromUserName, // Use host's name, not invitee's
              isBattle: true,
              battleId: battle.battleId,
              battleArtists: participants,
            ),
          ),
        ),
      );
    } catch (e) {
      // Close loading dialog
      if (scaffoldContext.mounted) {
        Navigator.of(scaffoldContext).pop(); // Close loading
      }

      debugPrint('Failed to accept battle invite: $e');
      if (scaffoldContext.mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(content: Text('Could not join battle: $e')),
        );
      }
    }
  }

  Future<void> _declineInvite(
    String inviteId,
    BuildContext dialogContext,
    BuildContext scaffoldContext,
  ) async {
    debugPrint('Declining battle invite: $inviteId');

    if (inviteId.trim().isEmpty) {
      if (scaffoldContext.mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text('Battle declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      await const BattleMatchingApi().respondToInvite(
        inviteId: inviteId,
        action: 'decline',
      );

      if (scaffoldContext.mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text('Battle declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to decline battle invite: $e');
      // Still show declined message even if API call fails
      if (scaffoldContext.mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text('Battle declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _startPollingFallback(BuildContext context, String userId) {
    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!_isListening || _isStopping || !context.mounted) return;

      try {
        final rows = await Supabase.instance.client
            .from('battle_invites')
            .select(
              'id,battle_id,from_uid,to_uid,status,created_at,expires_at,battle_title',
            )
            .eq('to_uid', userId)
            .eq('status', 'pending')
            .order('created_at', ascending: true)
            .limit(20);

        for (final raw in rows as List<dynamic>) {
          if (raw is! Map) continue;
          final invite = BattleInvite.fromMap(
            raw.map((k, v) => MapEntry(k.toString(), v)),
          );
          _onInviteReceived(context, invite);
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint('Battle invite polling fallback skipped: $e');
      }
    });
  }

  void _teardownChannel() {
    if (_channel != null) {
      try {
        _channel?.unsubscribe();
      } catch (_) {}
      try {
        Supabase.instance.client.removeChannel(_channel!);
      } catch (_) {}
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

    debugPrint(
      'Battle invite listener reconnect in ${delay.inSeconds}s (attempt=$_reconnectAttempt)',
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isListening && context.mounted) {
        if (kDebugMode)
          debugPrint('Retrying battle invite listener subscription...');
        startListening(context);
      }
    });
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
    unawaited(_stopRingtone());

    if (kDebugMode) debugPrint('🔌 Stopping battle invite listener');

    _teardownChannel();
    _isListening = false;
  }
}
