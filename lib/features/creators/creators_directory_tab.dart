import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'creator_profile.dart';
import 'creators_repository.dart';
import 'public_artist_profile_screen.dart';
import 'public_dj_profile_screen.dart';

class CreatorsDirectoryTab extends StatefulWidget {
  const CreatorsDirectoryTab({super.key});

  @override
  State<CreatorsDirectoryTab> createState() => _CreatorsDirectoryTabState();
}

class _CreatorsDirectoryTabState extends State<CreatorsDirectoryTab> {
  final CreatorsRepository _repo = CreatorsRepository();

  CreatorRole _role = CreatorRole.artist;
  String _query = '';

  late Future<List<CreatorProfile>> _future = _load();

  Future<List<CreatorProfile>> _load() {
    return _repo.list(role: _role, limit: 80, query: _query);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              SegmentedButton<CreatorRole>(
                segments: const [
                  ButtonSegment(value: CreatorRole.artist, label: Text('Artists')),
                  ButtonSegment(value: CreatorRole.dj, label: Text('DJs')),
                ],
                selected: {_role},
                onSelectionChanged: (s) {
                  setState(() {
                    _role = s.first;
                    _future = _load();
                  });
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: TextField(
            decoration: InputDecoration(
              hintText: _role == CreatorRole.artist ? 'Search artists' : 'Search DJs',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              setState(() {
                _query = v.trim();
                _future = _load();
              });
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<CreatorProfile>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
                      Text(
                        'Could not load ${_role == CreatorRole.artist ? 'artists' : 'DJs'}.'
                        '\n\nPlease try again.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  );
                }

                final items = snapshot.data ?? const <CreatorProfile>[];
                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
                      Text(
                        'No ${_role == CreatorRole.artist ? 'artists' : 'DJs'} found.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                  itemCount: items.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = items[index];
                    return ListTile(
                      tileColor: AppColors.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surface,
                        child: Text(
                          p.displayName.isEmpty ? '?' : p.displayName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      title: Text(p.displayName),
                      subtitle: (p.bio == null || p.bio!.isEmpty)
                          ? Text(
                              p.role == CreatorRole.artist ? 'Artist' : 'DJ',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            )
                          : Text(
                              p.bio!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                      onTap: () {
                        if (p.role == CreatorRole.artist) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PublicArtistProfileScreen(profile: p),
                            ),
                          );
                          return;
                        }

                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PublicDjProfileScreen(profile: p),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
