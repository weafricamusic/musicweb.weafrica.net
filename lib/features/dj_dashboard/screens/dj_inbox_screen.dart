import 'package:flutter/material.dart';
import 'dart:async';

import '../../../app/theme.dart';
import '../../inbox/services/creator_inbox_api.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_identity_service.dart';

class DjInboxScreen extends StatefulWidget {
  const DjInboxScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjInboxScreen> createState() => _DjInboxScreenState();
}

class _DjInboxScreenState extends State<DjInboxScreen> {
  final _identity = DjIdentityService();

  late Future<List<DjMessage>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DjMessage>> _load() async {
    _identity.requireDjUid();
    final rows = await CreatorInboxApi.instance.listMessages(role: 'dj', limit: 120);
    return rows.map(DjMessage.fromRow).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<DjMessage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Could not load messages. Please try again.',
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        final messages = snapshot.data ?? [];

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (messages.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text('No messages yet'),
              )
            else
              ...messages.map(
                (msg) => _MessageTile(
                  msg,
                  onOpen: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => _DjMessageDetailScreen(message: msg)),
                    );
                    if (updated == true && mounted) setState(() => _future = _load());
                  },
                  onMarkRead: () async {
                    await CreatorInboxApi.instance.markRead(role: 'dj', id: msg.id);
                    setState(() {
                      _future = _load();
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('DJ Inbox')),
      body: body,
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile(
    this.msg, {
    required this.onOpen,
    required this.onMarkRead,
  });

  final DjMessage msg;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: msg.isRead
              ? AppColors.surface2
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    msg.senderName ?? 'Fan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!msg.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(msg.content),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    msg.createdAt.toLocal().toString().split('.').first,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
                if (!msg.isRead)
                  TextButton(
                    onPressed: onMarkRead,
                    child: const Text('Mark as Read'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DjMessageDetailScreen extends StatefulWidget {
  const _DjMessageDetailScreen({required this.message});

  final DjMessage message;

  @override
  State<_DjMessageDetailScreen> createState() => _DjMessageDetailScreenState();
}

class _DjMessageDetailScreenState extends State<_DjMessageDetailScreen> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_markReadBestEffort());
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _markReadBestEffort() async {
    try {
      await CreatorInboxApi.instance.markRead(role: 'dj', id: widget.message.id);
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
      await CreatorInboxApi.instance.reply(
        role: 'dj',
        message: text,
        recipientUid: widget.message.senderId,
        recipientName: widget.message.senderName,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send reply. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.message.senderName ?? 'Fan';
    final body = widget.message.content;

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
          Text(
            'Reply',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800),
            ),
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