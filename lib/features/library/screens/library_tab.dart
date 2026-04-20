import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../app/widgets/gold_button.dart';
import '../../../app/widgets/stage_background.dart';
import '../../albums/album_detail_screen.dart';
import '../../creators/creators_directory_tab.dart';
import '../../player/playback_controller.dart';
import '../../player/player_routes.dart';
import '../../playlists/playlist_detail_screen.dart';
import '../../subscriptions/role_based_subscription_screen.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../subscriptions/services/consumer_entitlement_gate.dart';
import '../models/library_album.dart';
import '../models/library_item.dart';
import '../models/library_playlist.dart';
import '../models/library_track.dart';
import '../services/library_service.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/library_filter_chip.dart';
import '../widgets/library_grid_item.dart';
import '../widgets/library_list_item.dart';
import 'library_events_screen.dart';

enum LibraryViewMode {
  list,
  grid;

  IconData get icon =>
      this == LibraryViewMode.list ? Icons.view_list : Icons.grid_view;
}

enum LibraryTabType {
  tracks,
  albums,
  playlists,
  artists;

  String get displayName => name.toUpperCase();
}

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, this.initialFilter});

  /// Optional deep-link into a specific Tracks filter.
  ///
  /// Supported values: 'RECENTLY PLAYED', 'DOWNLOADED', 'LIKED'.
  final String? initialFilter;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> with TickerProviderStateMixin {
  final LibraryService _library = LibraryService();

  LibraryViewMode _viewMode = LibraryViewMode.list;
  int _selectedFilterIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  bool _loadingTracks = true;
  bool _loadingAlbums = true;
  bool _loadingPlaylists = true;

  String? _error;

  List<LibraryTrack> _likedTracks = const <LibraryTrack>[];
  List<LibraryTrack> _recentlyPlayed = const <LibraryTrack>[];
  List<LibraryTrack> _downloaded = const <LibraryTrack>[];
  List<LibraryAlbum> _albums = const <LibraryAlbum>[];
  List<LibraryPlaylist> _playlists = const <LibraryPlaylist>[];

  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );

  final List<String> _filters = const [
    'RECENTLY PLAYED',
    'DOWNLOADED',
    'LIKED',
  ];

  @override
  void initState() {
    super.initState();

    final initial = widget.initialFilter?.trim().toUpperCase();
    if (initial != null && initial.isNotEmpty) {
      final idx = _filters.indexWhere((f) => f.toUpperCase() == initial);
      if (idx >= 0) _selectedFilterIndex = idx;
    }

    // Never allow initial-load failures to surface as unhandled Zone errors
    // (especially noisy on Flutter Web).
    unawaited(
      _loadAll().catchError((e, st) {
        UserFacingError.log('LibraryTab initial load failed', e, st);
        if (!mounted) return;
        setState(() {
          _error = UserFacingError.message(e);
          _loadingTracks = false;
          _loadingAlbums = false;
          _loadingPlaylists = false;
        });
      }),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadTracks(),
      _loadAlbums(),
      _loadPlaylists(),
      _loadRecentsAndDownloads(),
    ]);
  }

  Future<void> _loadRecentsAndDownloads() async {
    final recentRes = await _library.getRecentlyPlayed(limit: 20);
    final dlRes = await _library.getDownloadedTracks(limit: 50);

    if (!mounted) return;
    setState(() {
      _recentlyPlayed = recentRes.data ?? const <LibraryTrack>[];
      _downloaded = dlRes.data ?? const <LibraryTrack>[];
    });
  }

  Future<void> _loadTracks() async {
    setState(() {
      _loadingTracks = true;
      _error = null;
    });

    final res = await _library.getLikedTracks(limit: 60);
    if (!mounted) return;

    res.fold(
      onSuccess: (tracks) => setState(() {
        _likedTracks = tracks;
        _loadingTracks = false;
      }),
      onFailure: (e) => setState(() {
        _error = UserFacingError.message(e);
        _loadingTracks = false;
      }),
    );
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loadingAlbums = true;
      _error = null;
    });

    final res = await _library.getSavedAlbums(limit: 60);
    if (!mounted) return;

    res.fold(
      onSuccess: (albums) => setState(() {
        _albums = albums;
        _loadingAlbums = false;
      }),
      onFailure: (e) => setState(() {
        _error = UserFacingError.message(e);
        _loadingAlbums = false;
      }),
    );
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _loadingPlaylists = true;
      _error = null;
    });

    final res = await _library.getPlaylists();
    if (!mounted) return;

    res.fold(
      onSuccess: (playlists) => setState(() {
        _playlists = playlists;
        _loadingPlaylists = false;
      }),
      onFailure: (e) => setState(() {
        _error = UserFacingError.message(e);
        _loadingPlaylists = false;
      }),
    );
  }

  Future<void> _refreshCurrent() async {
    final index = _tabController.index;
    if (index == 0) {
      await Future.wait([_loadTracks(), _loadRecentsAndDownloads()]);
      return;
    }
    if (index == 1) {
      await _loadAlbums();
      return;
    }
    if (index == 2) {
      await _loadPlaylists();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = base.colorScheme;

    final themed = base.copyWith(
      colorScheme: scheme.copyWith(
        primary: AppColors.stageGold,
        secondary: AppColors.stagePurple,
      ),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StageBackground(
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'YOUR LIBRARY',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: _isSearching ? 'Close search' : 'Search',
                        icon: Icon(_isSearching ? Icons.close : Icons.search),
                        onPressed: () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) _searchController.clear();
                          });
                        },
                      ),
                      IconButton(
                        tooltip: _viewMode == LibraryViewMode.list
                            ? 'Grid view'
                            : 'List view',
                        icon: Icon(_viewMode.icon),
                        onPressed: () {
                          setState(() {
                            _viewMode = _viewMode == LibraryViewMode.list
                                ? LibraryViewMode.grid
                                : LibraryViewMode.list;
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Events',
                        icon: const Icon(Icons.event),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LibraryEventsScreen(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshCurrent,
                      ),
                    ],
                  ),
                ),
                if (_isSearching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search your library…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _searchController.clear()),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return LibraryFilterChip(
                          label: _filters[index],
                          isSelected: index == _selectedFilterIndex,
                          onTap: () =>
                              setState(() => _selectedFilterIndex = index),
                        );
                      },
                    ),
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.stageGold,
                  labelColor: AppColors.stageGold,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: const [
                    Tab(text: 'TRACKS'),
                    Tab(text: 'ALBUMS'),
                    Tab(text: 'PLAYLISTS'),
                    Tab(text: 'ARTISTS'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _tracksView(),
                      _albumsView(),
                      _playlistsView(),
                      _artistsView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tracksView() {
    if (_loadingTracks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _errorState(title: 'Could not load tracks');
    }

    final items = _filteredTracks();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrent,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            LibraryEmptyState(
              title: 'No tracks here yet',
              subtitle: _selectedFilterIndex == 2
                  ? 'Like tracks while listening and they’ll appear here.'
                  : 'Try a different filter.',
            ),
            const SizedBox(height: 200),
          ],
        ),
      );
    }

    return _itemsView(items: items, onRefresh: _refreshCurrent);
  }

  Widget _albumsView() {
    if (_loadingAlbums) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _errorState(title: 'Could not load albums');
    }

    final items = _filteredAlbums();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrent,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            const LibraryEmptyState(
              title: 'No albums found',
              subtitle: 'Try a different search.',
            ),
            const SizedBox(height: 200),
          ],
        ),
      );
    }

    return _itemsView(items: items, onRefresh: _refreshCurrent);
  }

  Widget _playlistsView() {
    if (_loadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _errorState(
        title: 'Could not load playlists',
        action: GoldButton(
          onPressed: _createPlaylist,
          label: 'CREATE PLAYLIST',
          icon: Icons.add,
        ),
      );
    }

    final items = _filteredPlaylists();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrent,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            LibraryEmptyState(
              title: 'No playlists yet',
              subtitle: 'Create a playlist to start building your collection.',
              action: GoldButton(
                onPressed: _createPlaylist,
                label: 'CREATE PLAYLIST',
                icon: Icons.add,
              ),
            ),
            const SizedBox(height: 200),
          ],
        ),
      );
    }

    return _itemsView(items: items, onRefresh: _refreshCurrent);
  }

  Widget _artistsView() {
    // Reuse existing directory implementation.
    return const CreatorsDirectoryTab();
  }

  Widget _errorState({required String title, Widget? action}) {
    return RefreshIndicator(
      onRefresh: _refreshCurrent,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          LibraryEmptyState(
            title: title,
            subtitle: 'Please try again.',
            action: action,
          ),
          const SizedBox(height: 200),
        ],
      ),
    );
  }

  List<LibraryItem> _filteredTracks() {
    // Base list depends on filter selection.
    List<LibraryTrack> base;
    switch (_filters[_selectedFilterIndex]) {
      case 'RECENTLY PLAYED':
        base = _recentlyPlayed;
        break;
      case 'DOWNLOADED':
        base = _downloaded;
        break;
      case 'LIKED':
      default:
        base = _likedTracks;
        break;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return base;

    return base
        .where((t) {
          return t.title.toLowerCase().contains(query) ||
              t.subtitle.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<LibraryItem> _filteredAlbums() {
    final base = _albums;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return base;

    return base
        .where((a) {
          return a.title.toLowerCase().contains(query) ||
              a.subtitle.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<LibraryItem> _filteredPlaylists() {
    final base = _playlists;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return base;

    return base
        .where((p) => p.title.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Widget _itemsView({
    required List<LibraryItem> items,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: _viewMode == LibraryViewMode.grid
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return LibraryGridItem(
                  item: item,
                  onTap: () => _handleTap(item),
                );
              },
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];

                VoidCallback? onDownload;
                VoidCallback? onRemoveDownload;

                if (item is LibraryTrack) {
                  onDownload = item.isDownloaded
                      ? null
                      : () => _downloadTrack(item);
                  onRemoveDownload = item.isDownloaded
                      ? () => _removeDownloaded(item)
                      : null;
                }

                return LibraryListItem(
                  item: item,
                  onTap: () => _handleTap(item),
                  onDownload: onDownload,
                  onRemoveDownload: onRemoveDownload,
                  onPlayNext: item is LibraryTrack
                      ? () => _queueAction(item.track, playNext: true)
                      : null,
                  onAddToQueue: item is LibraryTrack
                      ? () => _queueAction(item.track, playNext: false)
                      : null,
                );
              },
            ),
    );
  }

  void _handleTap(LibraryItem item) {
    if (item is LibraryTrack) {
      _playTrack(item);
      return;
    }

    if (item is LibraryPlaylist) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlist: item.playlist),
        ),
      );
      return;
    }

    if (item is LibraryAlbum) {
      try {
        final album = item.album;
        if (album.id.isEmpty) {
          throw Exception('Album has no ID');
        }
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
        );
      } catch (e, st) {
        UserFacingError.log('LibraryTab open album failed', e, st);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open album. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
  }

  void _playTrack(LibraryTrack item) {
    final track = item.track;
    if (track.audioUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no audio URL yet.')),
      );
      return;
    }

    final controller = PlaybackController.instance;
    controller.play(track);
    openPlayer(context);
  }

  void _queueAction(Track track, {required bool playNext}) {
    final controller = PlaybackController.instance;
    if (controller.current == null) {
      controller.play(track);
      openPlayer(context);
      return;
    }

    controller.addToUpNext(track, toFront: playNext);

    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(playNext ? 'Will play next' : 'Added to queue')),
    );
  }

  Future<void> _downloadTrack(LibraryTrack item) async {
    if (!await _ensureCanDownload()) return;

    final res = await _library.downloadTrack(item.track);
    if (!mounted) return;

    res.fold(
      onSuccess: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved for offline.')));
        unawaited(_loadRecentsAndDownloads());
        unawaited(_loadTracks());
      },
      onFailure: (e) {
        UserFacingError.log('LibraryTab downloadTrack failed', e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Download failed. Please try again.',
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _ensureCanDownload() async {
    return ConsumerEntitlementGate.instance.ensureAllowed(
      context,
      capability: ConsumerCapability.downloads,
    );
  }

  Future<bool> _ensureCanCreatePlaylist() async {
    if (SubscriptionsController.instance.canCreatePlaylists) return true;
    return _promptSubscriptionUpgrade(
      title: 'Playlists require a subscription',
      message:
          'Upgrade to Premium Listener (or VIP Listener) to create playlists.',
    );
  }

  Future<bool> _promptSubscriptionUpgrade({
    required String title,
    required String message,
  }) async {
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Upgrade'),
            ),
          ],
        );
      },
    );

    if (upgrade == true && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const RoleBasedSubscriptionScreen()));
    }

    return false;
  }

  Future<void> _removeDownloaded(LibraryTrack item) async {
    final id = item.trackId;
    if (id == null) return;

    final res = await _library.removeDownloadedTrack(id);
    if (!mounted) return;

    res.fold(
      onSuccess: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed download.')));
        unawaited(_loadRecentsAndDownloads());
        unawaited(_loadTracks());
      },
      onFailure: (e) {
        UserFacingError.log('LibraryTab removeDownloadedTrack failed', e);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove download. Please try again.'),
          ),
        );
      },
    );
  }

  Future<void> _createPlaylist() async {
    if (!await _ensureCanCreatePlaylist()) return;

    // Avoid using BuildContext after an async gap if the widget was disposed.
    if (!mounted) return;

    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              hintText: 'e.g. My Favorites',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            GoldButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              label: 'CREATE',
              icon: Icons.check,
            ),
          ],
        );
      },
    );

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final res = await _library.createPlaylist(trimmed);
    if (!mounted) return;

    res.fold(
      onSuccess: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Playlist created.')));
        unawaited(_loadPlaylists());
      },
      onFailure: (e) {
        UserFacingError.log('LibraryTab createPlaylist failed', e);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create playlist. Please try again.'),
          ),
        );
      },
    );
  }
}
