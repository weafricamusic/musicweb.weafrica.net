import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../tracks/track.dart';

@immutable
class SongComment {
  const SongComment({
    required this.id,
    required this.songId,
    required this.userId,
    required this.comment,
    required this.createdAt,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String songId;
  final String userId;
  final String comment;
  final DateTime createdAt;
  final String? displayName;
  final String? avatarUrl;

  factory SongComment.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw.toString());

    return SongComment(
      id: (json['id'] ?? '').toString(),
      songId: (json['song_id'] ?? json['songId'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      comment: (json['comment'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['displayName'])?.toString(),
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'])?.toString(),
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}

class SongCommentsRepository {
  const SongCommentsRepository();

  Map<String, dynamic> _decodeBody(http.Response res) {
    final raw = res.body.trim();
    if (raw.isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  String _errorMessage(http.Response res) {
    try {
      final j = _decodeBody(res);
      final msg = (j['message'] ?? j['error'] ?? '').toString().trim();
      if (msg.isNotEmpty) return msg;
    } catch (_) {}

    return 'Request failed (HTTP ${res.statusCode}).';
  }

  Uri _commentsUri(String songId, {int? limit, int? offset}) {
    final base = ApiEnv.baseUrl;
    final encodedSongId = Uri.encodeComponent(songId);

    final query = <String, String>{
      if (limit != null) 'limit': limit.toString(),
      if (offset != null) 'offset': offset.toString(),
    };

    return Uri.parse('$base/api/songs/$encodedSongId/comments')
        .replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<List<SongComment>> list({required String songId, int limit = 50}) async {
    final res = await FirebaseAuthedHttp.get(
      _commentsUri(songId, limit: limit, offset: 0),
      headers: const {
        'Accept': 'application/json',
      },
      timeout: const Duration(seconds: 8),
      includeAuthIfAvailable: true,
      requireAuth: false,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorMessage(res));
    }

    final j = _decodeBody(res);
    final items = j['comments'];

    if (items is! List) return const <SongComment>[];

    return items
        .whereType<Map>()
        .map((m) => SongComment.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<SongComment> add({
    required String songId,
    required String comment,
    String? displayName,
    String? avatarUrl,
  }) async {
    final payload = <String, dynamic>{
      'comment': comment.trim(),
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
        'avatar_url': avatarUrl.trim(),
    };

    final res = await FirebaseAuthedHttp.post(
      _commentsUri(songId),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 10),
      includeAuthIfAvailable: true,
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorMessage(res));
    }

    final j = _decodeBody(res);
    final c = j['comment'];
    if (c is Map) {
      return SongComment.fromJson(c.cast<String, dynamic>());
    }

    throw StateError('Comment response invalid');
  }
}

Future<void> showSongCommentsSheet(BuildContext context, {required Track track}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (context) => _SongCommentsSheet(track: track),
  );
}

class _SongCommentsSheet extends StatefulWidget {
  const _SongCommentsSheet({required this.track});

  final Track track;

  @override
  State<_SongCommentsSheet> createState() => _SongCommentsSheetState();
}

class _SongCommentsSheetState extends State<_SongCommentsSheet> {
  static String _s(Object? v) => (v ?? '').toString().trim();

  final SongCommentsRepository _repo = const SongCommentsRepository();
  final TextEditingController _controller = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  Object? _error;
  List<SongComment> _comments = const <SongComment>[];

  String get _songId => _s(widget.track.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _songId;
    if (id.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _comments = const <SongComment>[];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _repo.list(songId: id, limit: 50);
      if (!mounted) return;
      setState(() {
        _comments = items;
        _loading = false;
      });
    } catch (e, st) {
      UserFacingError.log('Song comments load failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _shortUid(String uid) {
    final v = uid.trim();
    if (v.isEmpty) return 'User';
    if (v.length <= 10) return v;
    return '${v.substring(0, 6)}…${v.substring(v.length - 3)}';
  }

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _send() async {
    final id = _songId;
    if (id.isEmpty) return;

    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to comment.')),
      );
      return;
    }

    if (_sending) return;

    setState(() => _sending = true);

    try {
      final created = await _repo.add(
        songId: id,
        comment: trimmed,
        displayName: user.displayName ?? user.email,
        avatarUrl: user.photoURL,
      );

      if (!mounted) return;
      setState(() {
        _controller.clear();
        _comments = <SongComment>[created, ..._comments];
      });

      FocusScope.of(context).unfocus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment sent.')),
      );
    } catch (e, st) {
      UserFacingError.log('Song comment send failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(e, fallback: 'Could not send comment.'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.track.title.trim().isEmpty ? 'Song' : widget.track.title;
    final canComment = _songId.isNotEmpty;
    final user = FirebaseAuth.instance.currentUser;

    Widget body;
    if (!canComment) {
      body = const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Comments are not available for this track yet.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    } else if (_loading) {
      body = const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not load comments.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_comments.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'No comments yet.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _comments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final c = _comments[index];
            final name = _s(c.displayName);
            final label = name.isEmpty ? _shortUid(c.userId) : name;
            final avatarUrl = _s(c.avatarUrl);

            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.surface,
                  backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
                  child: avatarUrl.isNotEmpty
                      ? null
                      : Text(
                          label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800),
                        ),
                ),
                title: Text(
                  c.comment,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${label.isEmpty ? 'User' : label} • ${_formatTime(c.createdAt)}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          },
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          6,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Comments', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            body,
            const SizedBox(height: 12),
            if (canComment) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: user == null ? 'Sign in to comment…' : 'Write a comment…',
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.brandOrange),
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: (user == null || _sending) ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
