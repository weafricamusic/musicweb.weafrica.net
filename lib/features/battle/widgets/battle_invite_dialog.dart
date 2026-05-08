import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/config/api_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/navigation/app_navigator.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../auth/user_role.dart';
import '../../live/live_screen.dart';
import '../../live/models/live_args.dart';
import '../../live/models/live_battle.dart';

class BattleInviteDialog {
  static String? _activeInviteId;

  static String _s(Object? v) => (v ?? '').toString().trim();

  static void _toast(String message) {
    final ctx = AppNavigator.context;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<UserRole> _resolveCurrentUserRole(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      final roleId = _s(row?['role']).toLowerCase();
      final role = UserRoleX.fromId(roleId);
      return role == UserRole.consumer ? UserRole.artist : role;
    } catch (_) {
      return UserRole.artist;
    }
  }

  static Future<void> show(BuildContext context, Map<String, dynamic> data) async {
    final inviteId = _s(data['invite_id'] ?? data['inviteId'] ?? data['id']);
    
    if (inviteId.isEmpty) {
      debugPrint('BattleInviteDialog: inviteId is empty');
      return;
    }

    if (_activeInviteId == inviteId) return;
    _activeInviteId = inviteId;

    final fromUid = _s(data['from_uid'] ?? data['fromUid']);
    final battleId = _s(data['battle_id'] ?? data['battleId']);
    final channelId = _s(data['channel_id'] ?? data['channelId']);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        var busy = false;

        return StatefulBuilder(
          builder: (dialogCtx, setState) {
            Future<void> respond(String action) async {
              if (busy) return;

              setState(() {
                busy = true;
              });

              try {
                final battle = await _respondToInvite(inviteId: inviteId, action: action);
                if (!dialogCtx.mounted) return;
                Navigator.of(dialogCtx).pop();

                if (action == 'accept') {
                  final uid = Supabase.instance.client.auth.currentUser?.id;
                  if (uid == null) return;

                  final role = await _resolveCurrentUserRole(uid);
                  await _openBattleRoom(
                    channelId: _s(battle.channelId).isNotEmpty
                        ? battle.channelId
                        : (channelId.isNotEmpty ? channelId : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '')),
                    battleId: _s(battle.battleId).isNotEmpty ? battle.battleId : battleId,
                    role: role,
                    viewerId: uid,
                    battleArtists: <String>{
                      _s(battle.hostAId),
                      _s(battle.hostBId),
                      fromUid,
                      uid,
                    }.where((s) => s.isNotEmpty).toList(growable: false),
                  );
                }
              } catch (e, st) {
                UserFacingError.log('BattleInviteDialog.respond', e, st);
                _toast(
                  UserFacingError.message(
                    e,
                    fallback: 'Could not respond to invite. Please try again.',
                  ),
                );
              } finally {
                if (dialogCtx.mounted) {
                  setState(() {
                    busy = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Battle Invite'),
              content: const Text('You have been invited to a live battle.'),
              actions: [
                TextButton(
                  onPressed: busy ? null : () {
                    if (_activeInviteId == inviteId) _activeInviteId = null;
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Later'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () async {
                    await respond('decline');
                    if (_activeInviteId == inviteId) _activeInviteId = null;
                  },
                  child: const Text('Decline'),
                ),
                FilledButton(
                  onPressed: busy ? null : () async {
                    await respond('accept');
                    if (_activeInviteId == inviteId) _activeInviteId = null;
                  },
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (_activeInviteId == inviteId) _activeInviteId = null;
    });
  }

  static Future<LiveBattle> _respondToInvite({required String inviteId, required String action}) async {
    final act = action.trim().toLowerCase();
    final uri = Uri.parse('${ApiEnv.baseUrl}/api/battle/invite/respond');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(<String, Object?>{
        'invite_id': inviteId,
        'action': act,
      }),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (decoded is Map ? (decoded['message'] ?? decoded['error']) : null)?.toString();
      throw StateError(msg ?? 'Failed to respond to invite');
    }

    if (decoded is Map) {
      final raw = decoded['battle'] ?? decoded['data'] ?? decoded['result'];
      if (raw is Map) {
        final map = raw.map((k, v) => MapEntry(k.toString(), v));
        return LiveBattle.fromMap(Map<String, dynamic>.from(map));
      }
    }

    throw StateError('Invite response returned no battle data');
  }

  static Future<void> _openBattleRoom({
    required String channelId,
    required String battleId,
    required UserRole role,
    required String viewerId,
    required List<String> battleArtists,
  }) async {
    final ch = channelId.trim();
    if (ch.isEmpty) return;

    final hostName = role == UserRole.consumer ? 'Viewer' : role.label;

    await AppNavigator.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(
          args: LiveArgs(
            liveId: ch,
            channelId: ch,
            role: role,
            hostId: viewerId,
            hostName: hostName,
            isBattle: true,
            battleId: battleId.trim().isEmpty ? null : battleId.trim(),
            battleArtists: battleArtists,
          ),
        ),
      ),
    );
  }
}
