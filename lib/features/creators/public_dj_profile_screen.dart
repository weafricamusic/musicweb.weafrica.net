import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../dj_dashboard/models/dj_dashboard_models.dart';
import '../dj_dashboard/services/dj_dashboard_service.dart';
import 'creator_profile.dart';

class PublicDjProfileScreen extends StatefulWidget {
  const PublicDjProfileScreen({super.key, required this.profile});

  final CreatorProfile profile;

  @override
  State<PublicDjProfileScreen> createState() => _PublicDjProfileScreenState();
}

class _PublicDjProfileScreenState extends State<PublicDjProfileScreen> {
  final DjDashboardService _djService = DjDashboardService();
  late Future<_PublicDjProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PublicDjProfileData> _load() async {
    final client = Supabase.instance.client;
    final p = widget.profile;

    // Resolve Firebase UID for the DJ.
    var djUid = (p.userId ?? '').trim();

    // Prefer the canonical Firebase UID from the source table when available.
    // Some deployments may surface a Supabase UUID `user_id` via the directory view.
    final bestEffortFirebaseUid = await _bestEffortResolveDjFirebaseUid(
      client: client,
      djId: p.id,
    );
    if ((bestEffortFirebaseUid ?? '').trim().isNotEmpty) {
      djUid = bestEffortFirebaseUid!.trim();
    }
    if (djUid.isEmpty) {
      djUid = (await _bestEffortResolveDjUid(client: client, creatorProfileId: p.id)) ?? '';
    }

    // Load DJ profile row (followers/photo/bio).
    DjProfile? djProfile;
    if (djUid.isNotEmpty) {
      try {
        djProfile = await _djService.getProfile(djUid: djUid);
      } catch (_) {
        djProfile = null;
      }
    } else {
      // Last resort: match by stage_name.
      try {
        final rows = await client
            .from('dj_profile')
            .select('*')
            .ilike('stage_name', p.displayName)
            .limit(1);
        final list = rows as List<dynamic>;
        if (list.isNotEmpty) {
          djProfile = DjProfile.fromRow((list.first as Map).cast<String, dynamic>());
          djUid = djProfile.djUid;
        }
      } catch (_) {
        // ignore
      }
    }

    final displayName = (djProfile?.stageName ?? p.displayName).trim().isEmpty
        ? 'DJ'
        : (djProfile?.stageName ?? p.displayName).trim();
    final avatarUrl = (djProfile?.profilePhoto ?? p.avatarUrl)?.trim();
    final bio = (djProfile?.bio ?? p.bio)?.trim();

    final followers = djProfile?.followersCount ?? 0;

    // Mixes.
    List<DjSet> mixes = const <DjSet>[];
    if (djUid.isNotEmpty) {
      try {
        mixes = await _djService.listSets(djUid: djUid, limit: 50);
      } catch (_) {
        mixes = const <DjSet>[];
      }
    }

    // Genre specialty.
    final genres = _topGenres(mixes, top: 3);

    // Live schedule + past sessions.
    List<DjEvent> upcomingLives = const <DjEvent>[];
    List<DjEvent> pastLives = const <DjEvent>[];
    if (djUid.isNotEmpty) {
      try {
        upcomingLives = await _djService.listUpcomingLiveSchedule(djUid: djUid, limit: 20);
      } catch (_) {
        upcomingLives = const <DjEvent>[];
      }
      try {
        pastLives = await _djService.listPastLiveSessions(djUid: djUid, limit: 20);
      } catch (_) {
        pastLives = const <DjEvent>[];
      }
    }

    // Coins received.
    num coins = 0;
    if (djUid.isNotEmpty) {
      try {
        coins = await _djService.bestEffortCoinsReceived(djUid: djUid, limit: 2000);
      } catch (_) {
        coins = 0;
      }
    }

    return _PublicDjProfileData(
      djUid: djUid.isEmpty ? null : djUid,
      displayName: displayName,
      avatarUrl: (avatarUrl ?? '').isEmpty ? null : avatarUrl,
      bio: (bio ?? '').isEmpty ? null : bio,
      followers: followers,
      coinsReceived: coins,
      mixes: mixes,
      upcomingLives: upcomingLives,
      pastLives: pastLives,
      genres: genres,
    );
  }

  Future<String?> _bestEffortResolveDjUid({
    required SupabaseClient client,
    required String creatorProfileId,
  }) async {
    final id = creatorProfileId.trim();
    if (id.isEmpty) return null;

    try {
      final rows = await client.from('creator_profiles').select('user_id').eq('id', id).limit(1);
      final list = rows as List<dynamic>;
      if (list.isNotEmpty) {
        final m = (list.first as Map).cast<String, dynamic>();
        final uid = (m['user_id'] ?? '').toString().trim();
        return uid.isEmpty ? null : uid;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<String?> _bestEffortResolveDjFirebaseUid({
    required SupabaseClient client,
    required String djId,
  }) async {
    final id = djId.trim();
    if (id.isEmpty) return null;

    try {
      final rows = await client.from('djs').select('firebase_uid').eq('id', id).limit(1);
      final list = rows as List<dynamic>;
      if (list.isNotEmpty) {
        final m = (list.first as Map).cast<String, dynamic>();
        final uid = (m['firebase_uid'] ?? '').toString().trim();
        return uid.isEmpty ? null : uid;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  List<String> _topGenres(List<DjSet> mixes, {int top = 3}) {
    final counts = <String, int>{};
    for (final m in mixes) {
      final g = (m.genre ?? '').trim();
      if (g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(top).map((e) => e.key).toList(growable: false);
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return 'TBA';
    return DateFormat('EEE, MMM d • HH:mm').format(dt.toLocal());
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Future<void> _openReplay(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Profile'),
      ),
      body: FutureBuilder<_PublicDjProfileData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Could not load DJ profile. Please try again.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() {
                    _future = _load();
                  }),
                  child: const Text('Retry'),
                ),
              ],
            );
          }

          final data = snap.data;
          if (data == null) {
            return const Center(child: Text('No DJ profile data.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _card(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.surface,
                      backgroundImage: (data.avatarUrl ?? '').trim().isNotEmpty
                          ? NetworkImage(data.avatarUrl!)
                          : null,
                      child: (data.avatarUrl ?? '').trim().isNotEmpty
                          ? null
                          : Text(
                              data.displayName.isEmpty
                                  ? 'D'
                                  : data.displayName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900),
                            ),
                    ),
                    const SizedBox(width: 12),
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
                          const SizedBox(height: 4),
                          Text(
                            '👥 ${data.followers} followers • 💰 ${data.coinsReceived.toStringAsFixed(0)} coins',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (data.bio != null && data.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _card(
                  child: Text(data.bio!),
                ),
              ],

              const SizedBox(height: 14),
              Text(
                'Genre specialty',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _card(
                child: data.genres.isEmpty
                    ? const Text('Not set yet', style: TextStyle(color: AppColors.textMuted))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: data.genres
                            .map(
                              (g) => Chip(
                                label: Text(g),
                                side: const BorderSide(color: AppColors.border),
                                backgroundColor: AppColors.surface,
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),

              const SizedBox(height: 14),
              Text(
                'Mixes uploaded',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _card(
                child: data.mixes.isEmpty
                    ? const Text('No mixes uploaded yet.', style: TextStyle(color: AppColors.textMuted))
                    : Column(
                        children: data.mixes.take(10).map((m) {
                          final parts = <String>[];
                          final g = (m.genre ?? '').trim();
                          if (g.isNotEmpty) parts.add(g);
                          parts.add('${m.plays} plays');
                          parts.add('${m.coinsEarned} coins');
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(parts.join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(growable: false),
                      ),
              ),

              const SizedBox(height: 14),
              Text(
                'Live sessions schedule',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _card(
                child: data.upcomingLives.isEmpty
                    ? const Text('No scheduled live sessions.', style: TextStyle(color: AppColors.textMuted))
                    : Column(
                        children: data.upcomingLives.map((e) {
                          final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
                          final when = '${_fmtDate(e.startsAt)} → ${_fmtDate(e.endsAt)}';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event, color: AppColors.textMuted),
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(when, maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(growable: false),
                      ),
              ),

              const SizedBox(height: 14),
              Text(
                'Past live replays',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _card(
                child: data.pastLives.isEmpty
                    ? const Text('No past live sessions yet.', style: TextStyle(color: AppColors.textMuted))
                    : Column(
                        children: data.pastLives.take(10).map((e) {
                          final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
                          final when = _fmtDate(e.startsAt);
                          final replay = e.replayUrl;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.play_circle_outline, color: AppColors.textMuted),
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              replay == null ? '$when • Replay not uploaded' : '$when • Replay available',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: replay == null
                                ? null
                                : TextButton(
                                    onPressed: () => _openReplay(replay),
                                    child: const Text('Watch'),
                                  ),
                          );
                        }).toList(growable: false),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PublicDjProfileData {
  const _PublicDjProfileData({
    required this.djUid,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.followers,
    required this.coinsReceived,
    required this.mixes,
    required this.upcomingLives,
    required this.pastLives,
    required this.genres,
  });

  final String? djUid;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final int followers;
  final num coinsReceived;
  final List<DjSet> mixes;
  final List<DjEvent> upcomingLives;
  final List<DjEvent> pastLives;
  final List<String> genres;
}
