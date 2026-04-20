import 'package:flutter/material.dart';

import 'dj_playlists_screen.dart';
import 'dj_sets_screen.dart';

enum DjContentTab { sets, playlists }

class DjContentScreen extends StatefulWidget {
  const DjContentScreen({super.key, this.initialTab = DjContentTab.sets});

  final DjContentTab initialTab;

  @override
  State<DjContentScreen> createState() => _DjContentScreenState();
}

class _DjContentScreenState extends State<DjContentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Content'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sets'),
            Tab(text: 'Playlists'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          DjSetsScreen(),
          DjPlaylistsScreen(),
        ],
      ),
    );
  }
}