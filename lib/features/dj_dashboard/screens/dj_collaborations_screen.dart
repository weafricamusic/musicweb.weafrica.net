import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../services/dj_identity_service.dart';

class DjCollaborationsScreen extends StatefulWidget {
  const DjCollaborationsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjCollaborationsScreen> createState() => _DjCollaborationsScreenState();
}

class _DjCollaborationsScreenState extends State<DjCollaborationsScreen> {
  final _identity = DjIdentityService();

  late final String _djUid;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _djUid = _identity.requireDjUid();
    _future = _load();
  }

  bool _looksLikeNotConfigured(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('pgrst205') || msg.contains('collaboration_invites');
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final uid = _djUid;
      final rows = await Supabase.instance.client
          .from('collaboration_invites')
          .select('*')
          .or('from_uid.eq.$uid,to_uid.eq.$uid')
          .order('created_at', ascending: false)
          .limit(200);

      return (rows as List).whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (e) {
      if (_looksLikeNotConfigured(e)) {
        return const <Map<String, dynamic>>[];
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _shortId(String id) {
    final s = id.trim();
    if (s.isEmpty) return '—';
    if (s.length <= 10) return s;
    return '${s.substring(0, 10)}…';
  }

  DateTime? _parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

  Future<void> _createInviteDialog() async {
    final toCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var busy = false;
    String? error;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              Future<void> submit() async {
                if (busy) return;
                setState(() {
                  busy = true;
                  error = null;
                });

                final to = toCtrl.text.trim();
                final note = noteCtrl.text.trim();
                if (to.isEmpty) {
                  setState(() {
                    error = 'Enter a collaborator UID.';
                    busy = false;
                  });
                  return;
                }

                try {
                  await Supabase.instance.client.from('collaboration_invites').insert({
                    'from_uid': _djUid,
                    'from_role': 'dj',
                    'to_uid': to,
                    'message': note,
                    'status': 'pending',
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  });
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e, st) {
                  UserFacingError.log('DjCollaborationsScreen.sendInvite', e, st);
                  if (!ctx.mounted) return;
                  setState(() {
                    error = UserFacingError.message(
                      e,
                      fallback: 'Could not send invite. Please try again.',
                    );
                    busy = false;
                  });
                }
              }

              return AlertDialog(
                title: const Text('New collaboration request'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: toCtrl,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Collaborator UID',
                          hintText: 'Paste the creator UID',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteCtrl,
                        enabled: !busy,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Message (optional)',
                          hintText: 'Tell them what you want to collaborate on',
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!, style: const TextStyle(color: AppColors.brandBlue)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted || ok != true) return;

      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Collaboration request sent.')));
      await _refresh();
    } finally {
      toCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _updateStatus({required String id, required String status}) async {
    await Supabase.instance.client.from('collaboration_invites').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load collaborations. Please try again.',
            onRetry: _refresh,
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        final incoming = <Map<String, dynamic>>[];
        final outgoing = <Map<String, dynamic>>[];

        for (final r in rows) {
          final from = (r['from_uid'] ?? '').toString();
          final to = (r['to_uid'] ?? '').toString();
          if (to == _djUid) {
            incoming.add(r);
          } else if (from == _djUid) {
            outgoing.add(r);
          }
        }

        Widget section(String title, List<Map<String, dynamic>> list) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('No items', style: TextStyle(color: AppColors.textMuted)),
                )
              else
                ...list.map((r) => _InviteTile(
                      row: r,
                      myUid: _djUid,
                      shortId: _shortId,
                      parseDate: _parseDate,
                      onAccept: () async {
                        await _updateStatus(id: (r['id'] ?? '').toString(), status: 'accepted');
                        await _refresh();
                      },
                      onDecline: () async {
                        await _updateStatus(id: (r['id'] ?? '').toString(), status: 'declined');
                        await _refresh();
                      },
                      onCancel: () async {
                        await _updateStatus(id: (r['id'] ?? '').toString(), status: 'cancelled');
                        await _refresh();
                      },
                    )),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Collaborations', style: TextStyle(fontWeight: FontWeight.w900)),
                          SizedBox(height: 4),
                          Text(
                            'Send and manage collaboration requests.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _createInviteDialog,
                      icon: Icon(Icons.add),
                      label: Text('New'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              section('INCOMING', incoming),
              const SizedBox(height: 16),
              section('OUTGOING', outgoing),
              ],
            ),
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Collaborations'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.row,
    required this.myUid,
    required this.shortId,
    required this.parseDate,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final Map<String, dynamic> row;
  final String myUid;
  final String Function(String) shortId;
  final DateTime? Function(dynamic) parseDate;

  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final from = (row['from_uid'] ?? '').toString();
    final to = (row['to_uid'] ?? '').toString();
    final message = (row['message'] ?? '').toString().trim();
    final status = (row['status'] ?? 'pending').toString().trim().toLowerCase();
    final created = parseDate(row['created_at']);
    final isIncoming = to == myUid;
    final canAct = status == 'pending';

    final title = isIncoming ? 'From: ${shortId(from)}' : 'To: ${shortId(to)}';
    final subtitle = created == null
        ? status.toUpperCase()
        : '${created.toLocal().toString().split('.').first} • ${status.toUpperCase()}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message),
          ],
          if (canAct) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (isIncoming) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await onAccept();
                        } catch (e, st) {
                          UserFacingError.log('DjCollaborationsScreen.acceptInvite', e, st);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..removeCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFacingError.message(
                                    e,
                                    fallback: 'Action failed. Please try again.',
                                  ),
                                ),
                              ),
                            );
                        }
                      },
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await onDecline();
                        } catch (e, st) {
                          UserFacingError.log('DjCollaborationsScreen.declineInvite', e, st);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..removeCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFacingError.message(
                                    e,
                                    fallback: 'Action failed. Please try again.',
                                  ),
                                ),
                              ),
                            );
                        }
                      },
                      child: const Text('Decline'),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await onCancel();
                        } catch (e, st) {
                          UserFacingError.log('DjCollaborationsScreen.cancelInvite', e, st);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..removeCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFacingError.message(
                                    e,
                                    fallback: 'Action failed. Please try again.',
                                  ),
                                ),
                              ),
                            );
                        }
                      },
                      child: const Text('Cancel request'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
