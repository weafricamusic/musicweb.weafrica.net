import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../../app/widgets/media_card.dart';
import '../albums/album.dart';
import '../live_events/event_detail_screen.dart';
import '../live_events/live_event.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../pulse/pulse_engagement_repository.dart';
import '../pulse/reels/feed_screen.dart';
import '../videos/video.dart';
import 'creator_profile.dart';

class PublicArtistProfileScreen extends StatefulWidget {
  const PublicArtistProfileScreen({super.key, required this.profile});

  final CreatorProfile profile;

  @override
  State<PublicArtistProfileScreen> createState() => _PublicArtistProfileScreenState();
}

class _PublicArtistProfileScreenState extends State<PublicArtistProfileScreen> {
  late Future<_PublicArtistProfileData> _future;

  bool _togglingFollow = false;
  bool _following = false;
  int _followers = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PublicArtistProfileData> _load() async {
    final client = Supabase.instance.client;

    final profile = widget.profile;

    // Resolve Firebase UID (best-effort).
    var creatorUid = profile.userId;
    if (creatorUid == null || creatorUid.trim().isEmpty) {
      creatorUid = await _bestEffortResolveCreatorUid(client: client, creatorProfileId: profile.id);
    }

    // Resolve artists.id (best-effort).
    final artist = await _bestEffortLoadArtistRow(client: client, artistId: profile.id, uid: creatorUid);
    final artistId = (artist?['id'] ?? '').toString().trim();
    final resolvedArtistId = artistId.isEmpty ? null : artistId;

    final genreRaw = (artist?['genre'] ?? '').toString().trim();
    final genre = genreRaw.isEmpty ? null : genreRaw;

    final followers = await _bestEffortFollowersCount(
      client: client,
      artistRow: artist,
      artistId: resolvedArtistId,
    );

    final totalStreams = await _bestEffortTotalStreams(
      client: client,
      artistRow: artist,
      artistId: resolvedArtistId,
      uid: creatorUid,
    );

    final songs = await _bestEffortSongs(client: client, artistId: resolvedArtistId, uid: creatorUid);
    final albums = await _bestEffortAlbums(client: client, artistId: resolvedArtistId, uid: creatorUid);
    final videos = await _bestEffortVideos(client: client, artistId: resolvedArtistId, uid: creatorUid);
    final liveSessions = await _bestEffortLiveSessions(client: client, uid: creatorUid, displayName: profile.displayName);

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final following = await _bestEffortIsFollowing(
      client: client,
      currentUid: currentUid,
      artistId: resolvedArtistId,
    );

    if (mounted) {
      setState(() {
        _following = following;
        _followers = followers;
      });
    }

    return _PublicArtistProfileData(
      artistId: resolvedArtistId,
      creatorUid: creatorUid,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      bio: profile.bio,
      genre: genre,
      followers: followers,
      totalStreams: totalStreams,
      following: following,
      songs: songs,
      albums: albums,
      videos: videos,
      liveSessions: liveSessions,
    );
  }

  Future<String?> _bestEffortResolveCreatorUid({
    required SupabaseClient client,
    required String creatorProfileId,
  }) async {
    final id = creatorProfileId.trim();
    if (id.isEmpty) return null;

    try {
      final rows = await client.from('creator_profiles').select('user_id').eq('id', id).limit(1);
      final list = rows as List<dynamic>;
      if (list.isNotEmpty && list.first is Map) {
        final m = (list.first as Map).cast<String, dynamic>();
        final uid = (m['user_id'] ?? '').toString().trim();
        return uid.isEmpty ? null : uid;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<Map<String, dynamic>?> _bestEffortLoadArtistRow({
    required SupabaseClient client,
    required String? artistId,
    required String? uid,
  }) async {
    final id = (artistId ?? '').trim();
    final u = (uid ?? '').trim();

    try {
      if (id.isNotEmpty) {
        final rows = await client.from('artists').select('*').eq('id', id).limit(1);
        final list = rows as List<dynamic>;
        if (list.isNotEmpty && list.first is Map) {
          return (list.first as Map).cast<String, dynamic>();
        }
      }
    } catch (_) {
      // ignore
    }

    try {
      if (u.isNotEmpty) {
        final rows = await client
            .from('artists')
            .select('*')
            .or('user_id.eq.$u,firebase_uid.eq.$u')
            .limit(1);
        final list = rows as List<dynamic>;
        if (list.isNotEmpty && list.first is Map) {
          return (list.first as Map).cast<String, dynamic>();
        }
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<int> _bestEffortFollowersCount({
    required SupabaseClient client,
    required Map<String, dynamic>? artistRow,
    required String? artistId,
  }) async {
    if (artistRow != null) {
      for (final key in const ['followers_count', 'follower_count', 'followers']) {
        final v = artistRow[key];
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }

    final id = (artistId ?? '').trim();
    if (id.isEmpty) return 0;

    // Preferred: count rows in the canonical followers table.
    try {
      final rows = await client
          .from('followers')
          .select('id')
          .eq('artist_id', id)
          .limit(5000);
      return (rows as List<dynamic>).length;
    } catch (_) {
      // ignore
    }

    try {
      final rows = await client
          .from('pulse_follows')
          .select('user_id')
          .eq('artist_id', id)
          .eq('following', true)
          .order('updated_at', ascending: false)
          .limit(500);
      return (rows as List<dynamic>).length;
    } catch (_) {
      // ignore
    }

    return 0;
  }

  Future<int> _bestEffortTotalStreams({
    required SupabaseClient client,
    required Map<String, dynamic>? artistRow,
    required String? artistId,
    required String? uid,
  }) async {
    if (artistRow != null) {
      for (final key in const ['total_plays', 'plays_count', 'streams', 'total_streams']) {
        final v = artistRow[key];
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }

    final id = (artistId ?? '').trim();
    final u = (uid ?? '').trim();
    if (id.isEmpty && u.isEmpty) return 0;

    // Best-effort fallback: sum songs.streams/plays_count.
    try {
      dynamic q = client.from('songs').select('streams,plays_count,plays');
      if (id.isNotEmpty) {
        q = q.eq('artist_id', id);
      } else {
        // Legacy schema: songs.artist is a Firebase UID.
        q = q.eq('artist', u);
      }

      final rows = await q.order('created_at', ascending: false).limit(500);
      if (rows is! List) return 0;
      var sum = 0;
      for (final item in rows) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final v = m['streams'] ?? m['plays_count'] ?? m['plays'];
        if (v is num) {
          sum += v.toInt();
        } else {
          final parsed = int.tryParse(v?.toString() ?? '');
          if (parsed != null) sum += parsed;
        }
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Track>> _bestEffortSongs({
    required SupabaseClient client,
    required String? artistId,
    required String? uid,
  }) async {
    final id = (artistId ?? '').trim();
    final u = (uid ?? '').trim();
    if (id.isEmpty && u.isEmpty) return const <Track>[];

    try {
      Object rows;
      try {
        rows = await client
            .from('songs')
            .select('*,artists(name,stage_name,artist_name)')
            .eq('artist_id', id)
            .order('created_at', ascending: false)
            .limit(40);
      } catch (_) {
        rows = await client
            .from('songs')
            .select('*')
            .eq('artist_id', id)
            .order('created_at', ascending: false)
            .limit(40);
      }

      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Track.fromSupabase)
          .toList(growable: false);
    } catch (_) {
      // Legacy schema fallback.
      if (u.isEmpty) return const <Track>[];
      try {
        final rows = await client
            .from('songs')
            .select('*')
            .eq('artist', u)
            .order('created_at', ascending: false)
            .limit(40);
        return (rows as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(Track.fromSupabase)
            .toList(growable: false);
      } catch (_) {
        return const <Track>[];
      }
    }
  }

  Future<List<Album>> _bestEffortAlbums({
    required SupabaseClient client,
    required String? artistId,
    required String? uid,
  }) async {
    final id = (artistId ?? '').trim();
    final u = (uid ?? '').trim();
    if (id.isEmpty && u.isEmpty) return const <Album>[];

    try {
      Object rows;
      if (id.isNotEmpty) {
        rows = await client
            .from('albums')
            .select('*')
            .eq('artist_id', id)
            .order('created_at', ascending: false)
            .limit(40);
      } else {
        rows = await client
            .from('albums')
            .select('*')
            .eq('user_id', u)
            .order('created_at', ascending: false)
            .limit(40);
      }

      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Album.fromSupabaseLegacy)
          .toList(growable: false);
    } catch (_) {
      return const <Album>[];
    }
  }

  Future<List<Video>> _bestEffortVideos({
    required SupabaseClient client,
    required String? artistId,
    required String? uid,
  }) async {
    final id = (artistId ?? '').trim();
    final u = (uid ?? '').trim();
    if (id.isEmpty && u.isEmpty) return const <Video>[];

    try {
      dynamic q = client.from('videos').select('*');
      if (id.isNotEmpty) {
        try {
          q = q.eq('artist_id', id);
        } catch (_) {
          // ignore
        }
      }
      if (id.isEmpty && u.isNotEmpty) {
        q = q.eq('uploader_id', u);
      }

      final rows = await q.order('created_at', ascending: false).limit(40);
      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Video.fromSupabase)
          .where((v) => v.videoUri != null)
          .toList(growable: false);
    } catch (_) {
      if (u.isEmpty) return const <Video>[];
      try {
        final rows = await client
            .from('videos')
            .select('*')
            .eq('uploader_id', u)
            .order('created_at', ascending: false)
            .limit(40);
        return (rows as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(Video.fromSupabase)
            .where((v) => v.videoUri != null)
            .toList(growable: false);
      } catch (_) {
        return const <Video>[];
      }
    }
  }

  Future<List<LiveEvent>> _bestEffortLiveSessions({
    required SupabaseClient client,
    required String? uid,
    required String displayName,
  }) async {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return const <LiveEvent>[];

    try {
      final rows = await client
          .from('events')
          .select('*')
          .eq('host_user_id', u)
          .order('created_at', ascending: false)
          .limit(60);

      final all = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
      final normalized = all.map((r) {
        final map = Map<String, dynamic>.from(r);
        // Normalize schema variants.
        map['title'] ??= map['name'] ?? map['event_name'] ?? displayName;
        map['subtitle'] ??= map['venue'] ?? map['host_name'];
        return map;
      }).toList(growable: false);

      final events = normalized.map(LiveEvent.fromSupabase).toList(growable: false);
      final liveOnly = events.where((e) {
        final k = e.kind.trim().toLowerCase();
        return e.isLive == true || k == 'live';
      });
      return liveOnly.take(10).toList(growable: false);
    } catch (_) {
      return const <LiveEvent>[];
    }
  }

  Future<bool> _bestEffortIsFollowing({
    required SupabaseClient client,
    required String? currentUid,
    required String? artistId,
  }) async {
    final u = (currentUid ?? '').trim();
    final a = (artistId ?? '').trim();
    if (u.isEmpty || a.isEmpty) return false;

    // Preferred: canonical followers table (row existence == following).
    try {
      final rows = await client
          .from('followers')
          .select('id')
          .eq('user_id', u)
          .eq('artist_id', a)
          .limit(1);

      final list = rows as List<dynamic>;
      if (list.isNotEmpty) return true;
    } catch (_) {
      // ignore
    }

    try {
      final rows = await client
          .from('pulse_follows')
          .select('following')
          .eq('user_id', u)
          .eq('artist_id', a)
          .limit(1);

      final list = rows as List<dynamic>;
      if (list.isNotEmpty && list.first is Map) {
        final m = (list.first as Map).cast<String, dynamic>();
        final v = m['following'];
        if (v is bool) return v;
        final s = v?.toString().trim().toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
    } catch (_) {
      // ignore
    }

    return false;
  }

  List<Track> _queueFromAll(List<Track> tracks, int index) {
    final queue = <Track>[];
    for (var i = index + 1; i < tracks.length; i++) {
      final next = tracks[i];
      if (next.audioUri == null) continue;
      queue.add(next);
    }
    for (var i = 0; i < index; i++) {
      final next = tracks[i];
      if (next.audioUri == null) continue;
      queue.add(next);
    }
    return queue;
  }

  void _playTrack(
    Track t, {
    List<Track>? contextTracks,
    int? index,
  }) {
    if (t.audioUri == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('This track has no audio URL yet.')));
      return;
    }

    final queue = (contextTracks != null && index != null)
        ? _queueFromAll(contextTracks, index)
        : null;
    PlaybackController.instance.play(t, queue: queue);
    openPlayer(context);
  }

  Future<void> _toggleFollow(_PublicArtistProfileData data) async {
    final artistId = (data.artistId ?? '').trim();
    if (artistId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This artist is missing an ID.')),
      );
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to subscribe.')),
      );
      return;
    }

    if (_togglingFollow) return;
    setState(() => _togglingFollow = true);

    final next = !_following;
    try {
      await PulseEngagementRepository().setFollow(
        artistId: artistId,
        userId: currentUid,
        following: next,
      );

      if (!mounted) return;
      setState(() {
        _following = next;
        if (next) {
          _followers += 1;
        } else {
          _followers = (_followers - 1).clamp(0, 1 << 30);
        }
      });
    } catch (e) {
      UserFacingError.log('PublicArtistProfileScreen toggleFollow failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update subscription. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _togglingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.displayName),
      ),
      body: FutureBuilder<_PublicArtistProfileData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Could not load artist profile. Please try again.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('Retry'),
                ),
              ],
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('No artist data.'));
          }

          final avatarUrl = (data.avatarUrl ?? '').trim();
          final genre = (data.genre ?? '').trim();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.surface2,
                    backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
                    child: avatarUrl.isNotEmpty
                        ? null
                        : Text(
                            data.displayName.isEmpty
                                ? '?'
                                : data.displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (genre.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            genre,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _StatChip(label: 'Followers', value: _compactInt(_followers)),
                            const SizedBox(width: 10),
                            _StatChip(label: 'Streams', value: _compactInt(data.totalStreams)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 42,
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _togglingFollow ? null : () => _toggleFollow(data),
                            child: Text(_togglingFollow
                                ? 'Please wait…'
                                : (_following ? 'Subscribed' : 'Subscribe')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.bio != null && data.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  data.bio!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],

              const SizedBox(height: 18),
              _SectionTitle(title: 'Songs'),
              const SizedBox(height: 10),
              if (data.songs.isEmpty)
                Text(
                  'No songs yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                )
              else
                ...data.songs.asMap().entries.map(
                  (entry) {
                    final i = entry.key;
                    final t = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        tileColor: AppColors.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        leading: const Icon(Icons.music_note, color: AppColors.textMuted),
                        title: Text(t.title),
                        subtitle: Text(
                          [t.album, t.genre]
                              .where((s) => (s ?? '').trim().isNotEmpty)
                              .join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                        trailing: const Icon(Icons.play_arrow, color: AppColors.textMuted),
                        onTap: () => _playTrack(t, contextTracks: data.songs, index: i),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 18),
              _SectionTitle(title: 'Albums'),
              const SizedBox(height: 10),
              if (data.albums.isEmpty)
                Text(
                  'No albums yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                )
              else
                ...data.albums.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: AppColors.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      leading: const Icon(Icons.album, color: AppColors.textMuted),
                      title: Text(a.title),
                      subtitle: Text(
                        a.isPublished ? 'Published' : 'Unpublished',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 18),
              _SectionTitle(title: 'Videos'),
              const SizedBox(height: 10),
              if (data.videos.isEmpty)
                Text(
                  'No videos yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.videos.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final v = data.videos[index];
                      return MediaCard(
                        width: 140,
                        height: 180,
                        size: 140,
                        leadingIcon: Icons.play_circle,
                        title: v.title,
                        subtitle: v.category ?? 'Video',
                        imageUri: v.thumbnailUri,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ReelFeedScreen(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 18),
              _SectionTitle(title: 'Live sessions'),
              const SizedBox(height: 10),
              if (data.liveSessions.isEmpty)
                Text(
                  'No live sessions right now.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                )
              else
                ...data.liveSessions.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: AppColors.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      leading: const Icon(Icons.live_tv, color: AppColors.textMuted),
                      title: Text(e.title),
                      subtitle: Text(
                        <String?>[e.subtitle]
                          .where((s) => (s ?? '').trim().isNotEmpty)
                          .map((s) => s!.trim())
                          .join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EventDetailScreen(event: e),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PublicArtistProfileData {
  const _PublicArtistProfileData({
    required this.artistId,
    required this.creatorUid,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.genre,
    required this.followers,
    required this.totalStreams,
    required this.following,
    required this.songs,
    required this.albums,
    required this.videos,
    required this.liveSessions,
  });

  final String? artistId;
  final String? creatorUid;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? genre;
  final int followers;
  final int totalStreams;
  final bool following;
  final List<Track> songs;
  final List<Album> albums;
  final List<Video> videos;
  final List<LiveEvent> liveSessions;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

String _compactInt(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
