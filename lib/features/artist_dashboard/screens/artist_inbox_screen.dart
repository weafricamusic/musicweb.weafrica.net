import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../inbox/services/creator_inbox_api.dart';

class ArtistInboxScreen extends StatefulWidget {
  const ArtistInboxScreen({super.key});

  @override
  State<ArtistInboxScreen> createState() => _ArtistInboxScreenState();
}

class _ArtistInboxScreenState extends State<ArtistInboxScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    return CreatorInboxApi.instance.listMessages(role: 'artist', limit: 120);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox / Messages')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: 'Could not load messages.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No messages yet.', style: TextStyle(color: AppColors.textMuted)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final m = rows[i];
              final isRead = (m['read'] == true) || (m['is_read'] == true);
              final from = (m['sender_name'] ?? m['sender_id'] ?? m['from'] ?? m['sender'] ?? 'Fan').toString();
              final body = (m['message'] ?? m['body'] ?? '').toString();
              final date = (m['created_at'] ?? '').toString();

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Icon(isRead ? Icons.mail_outline : Icons.markunread_mailbox, color: AppColors.textMuted),
                  title: Text(from, style: TextStyle(fontWeight: isRead ? FontWeight.w700 : FontWeight.w900)),
                  subtitle: Text(
                    body.isEmpty ? '—' : body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  trailing: date.trim().isEmpty ? null : Text(date.split('.').first, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  onTap: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => _MessageDetailScreen(message: m)),
                    );
                    if (updated == true && mounted) setState(() => _future = _load());
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageDetailScreen extends StatefulWidget {
  const _MessageDetailScreen({required this.message});

  final Map<String, dynamic> message;

  @override
  State<_MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<_MessageDetailScreen> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _markReadBestEffort();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _markReadBestEffort() async {
    final id = (widget.message['id'] ?? '').toString();
    if (id.trim().isEmpty) return;
    try {
      await CreatorInboxApi.instance.markRead(role: 'artist', id: id);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      await CreatorInboxApi.instance.reply(
        role: 'artist',
        message: text,
        senderName: user?.displayName,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      Navigator.of(context).pop(true);
    } catch (e, st) {
      UserFacingError.log('ArtistInboxScreen._sendReply', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not send reply. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = (widget.message['sender_id'] ?? widget.message['from'] ?? 'Fan').toString();
    final body = (widget.message['message'] ?? widget.message['body'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Message')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From: $from', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(body.isEmpty ? '—' : body),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Reply', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _replyCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Type your reply…'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _sending ? null : _sendReply,
              icon: Icon(_sending ? Icons.hourglass_top : Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send reply'),
            ),
          ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
