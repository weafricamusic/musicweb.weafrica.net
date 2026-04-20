import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/constants/weafrica_power_voice.dart';
import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../auth/user_role.dart';
import '../../live/live_screen.dart';
import '../../live/models/live_args.dart';
import '../../live/models/live_battle.dart';
import '../../live/screens/go_live_setup_screen.dart';
import '../../live/services/battle_matching_api.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';

class DjLiveBattlesScreen extends StatefulWidget {
  const DjLiveBattlesScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjLiveBattlesScreen> createState() => _DjLiveBattlesScreenState();
}

class _DjLiveBattlesScreenState extends State<DjLiveBattlesScreen> {
  static const BattleMatchingApi _matchingApi = BattleMatchingApi();

  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<List<Map<String, dynamic>>> _future;
  Timer? _invitePoller;
  bool _inviteDialogOpen = false;
  final Set<String> _seenInviteIds = <String>{};
  RealtimeChannel? _inviteRealtime;

  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('DjLiveBattlesScreen init: uid=${currentUid ?? 'null'}');
    _future = _loadUpcoming();
    _startInvitePolling();
    unawaited(_startInviteRealtime());
  }

  @override
  void dispose() {
    _invitePoller?.cancel();
    unawaited(_inviteRealtime?.unsubscribe());
    super.dispose();
  }

  Future<void> _startInviteRealtime() async {
    // Best-effort: if realtime auth isn't configured locally, polling still works.
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('Listening for invites... uid=${currentUid ?? 'null'}');
      final uri = const ApiUriBuilder().build('/api/realtime/token');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: '{}',
        timeout: const Duration(seconds: 8),
        requireAuth: true,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Invite realtime token request failed: status=${res.statusCode} body=${res.body}');
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        debugPrint('Invite realtime token response was not a JSON object');
        return;
      }

      final token = (decoded['token'] ?? '').toString().trim();
      if (token.isEmpty) {
        debugPrint('Invite realtime token response did not include a token');
        return;
      }

      // Authenticate realtime only (does not affect PostgREST calls).
      Supabase.instance.client.realtime.setAuth(token);
      debugPrint('Invite realtime auth token applied');

      // Subscribe to inserts; on any new row, trigger the existing invite fetch+dialog.
      _inviteRealtime?.unsubscribe();
      _inviteRealtime = Supabase.instance.client
          .channel('public:battle_invites:inbox:${DateTime.now().millisecondsSinceEpoch}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'battle_invites',
          callback: (payload) {
            debugPrint('Invite received: ${payload.newRecord}');
            unawaited(_pollInvites(showOnlyNew: true));
          },
        )
        ..subscribe((status, [error]) {
          debugPrint('Invite realtime subscription status=$status error=${error ?? 'none'}');
        });
    } catch (error, stackTrace) {
      debugPrint('Invite realtime bootstrap failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void _startInvitePolling() {
    unawaited(_pollInvites(showOnlyNew: true));
    _invitePoller?.cancel();
    _invitePoller = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_pollInvites(showOnlyNew: true)),
    );
  }

  Future<List<Map<String, dynamic>>> _loadUpcoming() async {
    final uid = _identity.requireDjUid();

    try {
      final rows = await Supabase.instance.client
          .from('dj_events')
          .select('id,dj_id,event_type,starts_at,ends_at,status,metadata')
          .eq('dj_id', uid)
          .order('starts_at', ascending: true)
          .limit(100);

      return (rows as List).whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openBattle(BuildContext context, LiveBattle battle) {
    final uid = _identity.requireDjUid();
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final hostName = (name != null && name.isNotEmpty) ? name : UserRole.dj.label;

    final artists = <String>[];
    if (battle.hostAId != null && battle.hostAId!.trim().isNotEmpty) artists.add(battle.hostAId!.trim());
    if (battle.hostBId != null && battle.hostBId!.trim().isNotEmpty) artists.add(battle.hostBId!.trim());

    _open(
      context,
      LiveScreen(
        args: LiveArgs(
          liveId: battle.channelId,
          channelId: battle.channelId,
          role: UserRole.dj,
          hostId: uid,
          hostName: hostName,
          isBattle: true,
          battleId: battle.battleId,
          battleArtists: artists,
        ),
      ),
    );
  }

  Future<void> _showBattleInvitesDialog(BuildContext context, List<BattleInvite> invites) async {
    if (invites.isEmpty) return;

    _inviteDialogOpen = true;
    _seenInviteIds.addAll(invites.map((invite) => invite.id));

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var list = List<BattleInvite>.from(invites);
        var busy = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> respond(BattleInvite inv, String action) async {
              if (busy) return;
              setState(() { busy = true; });
              try {
                final battle = await _matchingApi.respondToInvite(inviteId: inv.id, action: action);
                if (!ctx.mounted) return;
                if (action == 'accept') {
                  Navigator.of(ctx).pop();
                  if (!context.mounted) return;
                  _openBattle(context, battle);
                  return;
                }

                setState(() {
                  list.removeWhere((x) => x.id == inv.id);
                });
              } catch (e) {
                UserFacingError.log('DjLiveBattlesScreen respondToInvite failed', e);
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Could not respond to invite. Please try again.')),
                );
              } finally {
                if (ctx.mounted) setState(() { busy = false; });
              }
            }

            return AlertDialog(
              title: Text('Battle invites (${list.length})'),
              content: SizedBox(
                width: 420,
                child: list.isEmpty
                    ? const Text(WeAfricaPowerVoice.emptyBattleInvites)
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final inv = list[i];
                          final fromName = inv.fromUserName.trim().isNotEmpty
                              ? inv.fromUserName.trim()
                              : (inv.fromUid.length <= 10 ? inv.fromUid : '${inv.fromUid.substring(0, 10)}…');
                          final exp = inv.expiresAt;
                          final expText = ' • expires ${exp.toLocal().toString().split('.').first}';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                              color: AppColors.surface2,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('From: $fromName', style: Theme.of(ctx).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text('Battle invite$expText', style: Theme.of(ctx).textTheme.bodySmall),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: busy ? null : () => respond(inv, 'accept'),
                                        child: const Text('Accept'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: busy ? null : () => respond(inv, 'decline'),
                                        child: const Text('Decline'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );

    _inviteDialogOpen = false;
  }

  Future<void> _pollInvites({required bool showOnlyNew}) async {
    if (!mounted || _inviteDialogOpen) return;

    try {
      final invites = await _matchingApi.listInvites(box: 'inbox', status: 'pending', limit: 25);
      debugPrint('Invite poll result: count=${invites.length} showOnlyNew=$showOnlyNew');
      if (!mounted || invites.isEmpty) return;

      final unseen = invites.where((invite) => !_seenInviteIds.contains(invite.id)).toList(growable: false);
      debugPrint('Invite poll unseen count=${unseen.length}');
      if (showOnlyNew && unseen.isEmpty) return;

      await _showBattleInvitesDialog(context, showOnlyNew ? unseen : invites);
    } catch (error, stackTrace) {
      debugPrint('Invite poll failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _quickMatchBattle(BuildContext context) async {
    // First: show pending invites (inbox).
    try {
      final invites = await _matchingApi.listInvites(box: 'inbox', status: 'pending', limit: 25);
      if (!context.mounted) return;
      if (invites.isNotEmpty) {
        await _showBattleInvitesDialog(context, invites);
        return;
      }
    } catch (_) {
      // Ignore invite list failures and fall back to quick match.
    }

    var started = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var note = 'Finding an opponent…';
        var cancelled = false;

        Future<void> run() async {
          try {
            final initial = await _matchingApi.quickMatchJoin(role: 'dj');
            if (!ctx.mounted) return;
            if (initial != null) {
              Navigator.of(ctx).pop();
              if (!context.mounted) return;
              _openBattle(context, initial);
              return;
            }

            for (var i = 0; i < 30; i++) {
              if (!ctx.mounted || cancelled) return;
              await Future<void>.delayed(const Duration(seconds: 2));
              final polled = await _matchingApi.quickMatchPoll();
              if (!ctx.mounted || cancelled) return;
              if (polled != null) {
                Navigator.of(ctx).pop();
                if (!context.mounted) return;
                _openBattle(context, polled);
                return;
              }
            }

            if (!ctx.mounted) return;
            note = 'No match found yet. Try again.';
          } catch (e) {
            if (!ctx.mounted) return;
            UserFacingError.log('DjLiveBattlesScreen quickMatch failed', e);
            note = 'Could not find a match. Please try again.';
          } finally {
            try {
              await _matchingApi.quickMatchCancel();
            } catch (_) {}
            if (ctx.mounted && note != 'Finding an opponent…') {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(note)));
              Navigator.of(ctx).pop();
            }
          }
        }

        if (!started) {
          started = true;
          Future<void>.microtask(run);
        }

        return AlertDialog(
          title: const Text('Quick match (DJ Battle)'),
          content: Text(note),
          actions: [
            TextButton(
              onPressed: () async {
                cancelled = true;
                try {
                  await _matchingApi.quickMatchCancel();
                } catch (_) {}
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _goLive(BuildContext context) async {
    final djUid = _identity.requireDjUid();
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final hostName = (name != null && name.isNotEmpty) ? name : UserRole.dj.label;

    _open(
      context,
      GoLiveSetupScreen(
        role: UserRole.dj,
        hostId: djUid,
        hostName: hostName,
      ),
    );
  }

  Future<void> _scheduleLiveDialog() async {
    final uid = _identity.requireDjUid();

    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (!mounted) return;
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
    );
    if (!mounted) return;
    if (pickedTime == null) return;

    final start = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final durationCtrl = TextEditingController(text: '60');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Schedule live'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Start: ${start.toString().split('.').first}', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              TextField(
                controller: durationCtrl,
                decoration: const InputDecoration(labelText: 'Duration (minutes)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Schedule')),
          ],
        ),
      );

      if (ok != true) return;

      final mins = int.tryParse(durationCtrl.text.trim()) ?? 60;
      final end = start.add(Duration(minutes: mins.clamp(15, 480)));

      await _service.scheduleLive(
        djUid: uid,
        startsAt: start.toUtc(),
        endsAt: end.toUtc(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Live scheduled.')));
      setState(() { _future = _loadUpcoming(); });
    } catch (e) {
      UserFacingError.log('DjLiveBattlesScreen scheduleLive failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not schedule live. Please try again.')));
    } finally {
      durationCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;
        final rows = snap.data ?? const <Map<String, dynamic>>[];

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SectionTitle('Go live'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _goLive(context),
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Start live'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _quickMatchBattle(context),
                    icon: const Icon(Icons.sports_mma),
                    label: const Text('Quick battle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // REMOVED: "Start battle" button - creation now via Go Live with Battle Mode ON
            OutlinedButton.icon(
              onPressed: _scheduleLiveDialog,
              icon: const Icon(Icons.event),
              label: const Text('Schedule live session'),
            ),

            const SizedBox(height: 18),
            _SectionTitle('Upcoming sessions'),
            const SizedBox(height: 10),
            if (waiting)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (snap.hasError)
              const Text('Could not load upcoming sessions.', style: TextStyle(color: AppColors.textMuted))
            else if (rows.isEmpty)
              const Text('No upcoming sessions.', style: TextStyle(color: AppColors.textMuted))
            else
              ...rows.take(20).map((e) {
                final type = (e['event_type'] ?? 'live').toString();
                final status = (e['status'] ?? '').toString();
                final starts = (e['starts_at'] ?? '').toString();
                final ends = (e['ends_at'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type, style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('Status: $status', style: const TextStyle(color: AppColors.textMuted)),
                              if (starts.trim().isNotEmpty) Text('Start: $starts', style: const TextStyle(color: AppColors.textMuted)),
                              if (ends.trim().isNotEmpty) Text('End: $ends', style: const TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Live & Battles')),
      body: body,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}