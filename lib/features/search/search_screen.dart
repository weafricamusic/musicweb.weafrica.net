import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../tracks/tracks_repository.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _searchDebounce;

  static const _prefsRecentKey = 'recent_searches';
  static const _maxRecent = 8;

  List<String> _recent = const <String>[];
  bool _loadingRecent = true;

  Future<List<Track>>? _results;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsRecentKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _recent = list.where((e) => e.trim().isNotEmpty).toList(growable: false);
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = const <String>[];
        _loadingRecent = false;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _runSearch(String query, {bool saveRecent = false}) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }

    setState(() {
      _results = TracksRepository().search(q, limit: 40);
    });

    if (saveRecent) {
      _saveRecent(q);
    }
  }

  void _scheduleAutoSearch(String query) {
    _searchDebounce?.cancel();
    final q = query.trim();

    if (q.isEmpty) {
      _runSearch('');
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _runSearch(q, saveRecent: false);
    });
  }

  Future<void> _saveRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final next = <String>[q, ..._recent.where((e) => e.toLowerCase() != q.toLowerCase())]
        .take(_maxRecent)
        .toList(growable: false);

    setState(() => _recent = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsRecentKey, next);
    } catch (_) {
      // Best-effort.
    }
  }

  void _applyQueryAndSearch(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    _runSearch(value, saveRecent: true);
  }

  Widget _sectionTitle(BuildContext context, String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
        ),
      ],
    );
  }

  Widget _pillButton(BuildContext context, {required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.search, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              'SEARCH',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _runSearch(value, saveRecent: true),
            onChanged: (v) {
              setState(() {});
              _scheduleAutoSearch(v);
            },
            decoration: InputDecoration(
              hintText: 'Search tracks or artists',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        _searchDebounce?.cancel();
                        _runSearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_results == null) ...[
            _sectionTitle(context, 'Recent Searches'),
            const SizedBox(height: 8),
            if (_loadingRecent)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_recent.isEmpty)
              Text(
                'No recent searches yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              )
            else
              ..._recent.map(
                (q) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('•', style: TextStyle(color: AppColors.textMuted, fontSize: 18)),
                  title: Text(q),
                  onTap: () => _applyQueryAndSearch(q),
                ),
              ),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            Text(
              'Type a query to search tracks and artists from the backend.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ] else ...[
            _sectionTitle(context, 'Results'),
            const SizedBox(height: 8),
            FutureBuilder<List<Track>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Search failed. Please try again.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  );
                }

                final results = snapshot.data ?? const <Track>[];
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'No results.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final track = results[index];
                    return ListTile(
                      tileColor: AppColors.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      leading: const Icon(Icons.music_note, color: AppColors.textMuted),
                      title: Text(track.title),
                      subtitle: Text(
                        track.artist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                      trailing: const Icon(Icons.play_arrow),
                      onTap: () {
                        final playback = PlaybackController.instance;
                        final queue = <Track>[];
                        for (final t in results) {
                          if (identical(t, track)) continue;
                          if (track.id != null && t.id != null && t.id == track.id) continue;
                          if (t.audioUri == null) continue;
                          queue.add(t);
                        }
                        playback.play(track, queue: queue);
                        openPlayer(context);
                      },
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
