import 'package:flutter/material.dart';

import '../models/artist_dashboard_models.dart';
import '../services/artist_dashboard_service.dart';
import '../widgets/artist_profile_main_view.dart';
import 'artist_profile_settings_screen.dart';
import '../../settings/creator_settings_screen.dart';

class ArtistProfileScreen extends StatefulWidget {
  const ArtistProfileScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  final ArtistDashboardService _service = ArtistDashboardService();
  late Future<ArtistDashboardHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ArtistDashboardHomeData> _load() {
    return _service.loadHome();
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ArtistProfileSettingsScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreatorSettingsScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Widget _buildBody() {
    return FutureBuilder<ArtistDashboardHomeData>(
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
                'Could not load your artist profile.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _future = _load();
                  });
                },
                child: const Text('Retry'),
              ),
            ],
          );
        }

        final data = snapshot.data ??
            const ArtistDashboardHomeData(
              followersCount: 0,
              totalPlays: 0,
              totalEarnings: 0,
              coinBalance: 0,
              recentSongs: [],
              recentVideos: <ArtistVideoItem>[],
              notificationsCount: 0,
              recentNotifications: <ArtistNotificationItem>[],
              unreadMessagesCount: 0,
            );

        return ArtistProfileMainView(
          dashboardData: data,
          onEditProfile: _openEditProfile,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: body,
    );
  }
}