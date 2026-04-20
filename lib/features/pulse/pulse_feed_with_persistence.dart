import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'pulse_engagement_repository.dart';
import 'pulse_feed_item.dart';

/// WEAFRICA MUSIC — REAL-TIME ENGAGEMENT WITH SUPABASE (Prototype)
///
/// Persists likes/comments/follows into Supabase tables.
///
/// Notes:
/// - App auth is Firebase; we store Firebase UID in Supabase as `user_id` (text).
/// - With an anon Supabase key, RLS cannot truly verify Firebase UID.
///   This is fine for prototypes; for production, move writes to an Edge Function.
class PulseFeedWithPersistence extends StatefulWidget {
  const PulseFeedWithPersistence({
    super.key,
    required this.videos,
    PulseEngagementRepository? repository,
  }) : _repository = repository;

  /// Expected keys per item:
  /// - `id` (uuid string of public.videos.id) (required for persistence)
  /// - `url`
  /// - `song`
  /// - `artist`
  /// - `artist_id` (optional; defaults to `artist`)
  final List<Map<String, String>> videos;

  final PulseEngagementRepository? _repository;

  @override
  State<PulseFeedWithPersistence> createState() =>
      _PulseFeedWithPersistenceState();
}

class _PulseFeedWithPersistenceState extends State<PulseFeedWithPersistence> {
  late final PulseEngagementRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = widget._repository ?? PulseEngagementRepository();
  }

  String? get _firebaseUid => FirebaseAuth.instance.currentUser?.uid;

  void _requireLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in to interact.')),
    );
  }

  Future<void> _handleLike({required String videoId}) async {
    final uid = _firebaseUid;
    if (uid == null) return _requireLogin();

    try {
      await _repo.setLike(videoId: videoId, userId: uid, liked: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not like right now.')),
      );
    }
  }

  Future<void> _handleComment({required String videoId, required String song}) async {
    final uid = _firebaseUid;
    if (uid == null) return _requireLogin();

    final controller = TextEditingController();
    final comment = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comment on $song',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Write a comment…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => Navigator.of(context).pop(v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (comment == null || comment.trim().isEmpty) return;

    try {
      await _repo.addComment(videoId: videoId, userId: uid, comment: comment);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send comment.')),
      );
    }
  }

  Future<void> _handleFollow({required String artistId}) async {
    final uid = _firebaseUid;
    if (uid == null) return _requireLogin();

    try {
      await _repo.setFollow(artistId: artistId, userId: uid, following: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not follow right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: widget.videos.length,
      itemBuilder: (context, index) {
        final video = widget.videos[index];

        final videoId = video['id'];
        final url = video['url'] ?? '';
        final song = video['song'] ?? 'Unknown';
        final artist = video['artist'] ?? 'Unknown';
        final artistId = video['artist_id'] ?? artist;

        // If no video id is provided, we still render the UI but persistence
        // callbacks become no-ops.
        final canPersist = videoId != null && videoId.isNotEmpty;

        return PulseFeedItem(
          videoUrl: url,
          songTitle: song,
          artistName: artist,
          onLike: canPersist ? () => _handleLike(videoId: videoId) : () {},
          onComment: canPersist
              ? () => _handleComment(videoId: videoId, song: song)
              : () {},
          onFollow: () => _handleFollow(artistId: artistId),
        );
      },
    );
  }
}
