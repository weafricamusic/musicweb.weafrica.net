import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/studio_card.dart';
import '../../auth/user_role.dart';
import '../../creator/upload_video_screen.dart';
import '../../videos/screens/video_playback_screen.dart';
import '../../videos/video.dart';

class CreatorPulseUploadsScreen extends StatefulWidget {
  const CreatorPulseUploadsScreen({
    super.key,
    this.showAppBar = true,
    this.uploadIntent = UserRole.artist,
  });

  final bool showAppBar;
  final UserRole uploadIntent;

  @override
  State<CreatorPulseUploadsScreen> createState() => _CreatorPulseUploadsScreenState();
}

class _CreatorPulseUploadsScreenState extends State<CreatorPulseUploadsScreen> {
  late Future<List<_CreatorVideoRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Video>> _loadVideos({required SupabaseClient client, required String uid}) async {
    List<Map<String, dynamic>> asRows(dynamic rows) =>
        (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);

    List<Video> parse(dynamic rows) => asRows(rows)
        .map(Video.fromSupabase)
        .where((v) => v.videoUri != null)
        .toList(growable: false);

    final rows = await client
        .from('videos')
        .select('*')
        .eq('uploader_id', uid)
        .order('created_at', ascending: false)
        .limit(80);
    return parse(rows);
  }

  Map<String, int> _countVideoIds(dynamic rows) {
    final counts = <String, int>{};
    for (final row in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
      final id = (row['video_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  Future<Map<String, int>> _countByVideoId({
    required SupabaseClient client,
    required String table,
    required List<String> videoIds,
    bool likedOnly = false,
  }) async {
    if (videoIds.isEmpty) return const <String, int>{};

    var q = client.from(table).select('video_id').inFilter('video_id', videoIds);
    if (likedOnly) {
      q = q.eq('liked', true);
    }
    final rows = await q;
    return _countVideoIds(rows);
  }

  Future<List<_CreatorVideoRow>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) return const <_CreatorVideoRow>[];

    final client = Supabase.instance.client;

    final videos = await _loadVideos(client: client, uid: uid);
    if (videos.isEmpty) return const <_CreatorVideoRow>[];

    final ids = videos
        .map((v) => v.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final pulseLikes = await _countByVideoId(
      client: client,
      table: 'pulse_likes',
      videoIds: ids,
      likedOnly: true,
    );
    final videoLikes = await _countByVideoId(
      client: client,
      table: 'video_likes',
      videoIds: ids,
    );
    final pulseComments = await _countByVideoId(
      client: client,
      table: 'pulse_comments',
      videoIds: ids,
    );
    final videoComments = await _countByVideoId(
      client: client,
      table: 'video_comments',
      videoIds: ids,
    );

    return videos.map((v) {
      final fromLikesTables = math.max(pulseLikes[v.id] ?? 0, videoLikes[v.id] ?? 0);
      final fromCommentsTables = math.max(pulseComments[v.id] ?? 0, videoComments[v.id] ?? 0);

      final likes = math.max(v.likesCount ?? 0, fromLikesTables);
      final comments = math.max(v.commentsCount ?? 0, fromCommentsTables);

      return _CreatorVideoRow(
        video: v,
        likesCount: likes,
        commentsCount: comments,
      );
    }).toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _openUpload() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UploadVideoScreen(creatorIntent: widget.uploadIntent)),
    );
  }

  void _play(Video video) {
    if (video.videoUri == null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('This video has no playable URL yet.')));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlaybackScreen(video: video)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;

    final content = FutureBuilder<List<_CreatorVideoRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return _ErrorBox(
            text: 'Could not load your uploads.',
            onRetry: _refresh,
          );
        }

        final videos = snap.data ?? const <_CreatorVideoRow>[];

        return RefreshIndicator(
          color: AppColors.stageGold,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              StudioCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your Pulse uploads', style: TextStyle(fontWeight: FontWeight.w900)),
                          SizedBox(height: 4),
                          Text(
                            'These are the videos you uploaded. Tap any card to play.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (!showAppBar) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: _openUpload,
                        icon: const Icon(Icons.add),
                        label: const Text('Upload'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (videos.isEmpty)
                StudioCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('No uploads yet', style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text(
                        'Upload your first video to start building your Pulse catalog.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              else
                ...videos.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _VideoCard(
                      video: row.video,
                      likesCount: row.likesCount,
                      commentsCount: row.commentsCount,
                      onTap: () => _play(row.video),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (showAppBar) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Pulse • My Uploads'),
          actions: [
            IconButton(
              tooltip: 'Upload',
              onPressed: _openUpload,
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: content,
      );
    }

    return Container(color: AppColors.background, child: content);
  }
}

class _CreatorVideoRow {
  const _CreatorVideoRow({
    required this.video,
    required this.likesCount,
    required this.commentsCount,
  });

  final Video video;
  final int likesCount;
  final int commentsCount;
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.likesCount,
    required this.commentsCount,
    required this.onTap,
  });

  final Video video;
  final int likesCount;
  final int commentsCount;
  final VoidCallback onTap;

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUri;

    return StudioCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 72,
              height: 72,
              color: AppColors.surface,
              child: thumb == null
                  ? const Icon(Icons.movie_outlined, color: AppColors.textMuted)
                  : Image.network(
                      thumb.toString(),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const Icon(Icons.movie_outlined, color: AppColors.textMuted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtDate(video.createdAt)} • Likes $likesCount • Comments $commentsCount',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.play_circle_fill, color: AppColors.stageGold, size: 30),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StudioCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
