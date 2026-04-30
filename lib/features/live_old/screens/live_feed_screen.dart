import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../../../app/utils/app_result.dart';
import '../models/live_session_model.dart' show LiveSession;
import 'consumer_battle_screen.dart';
import '../services/live_feed_discover_service.dart';
import '../services/battle_service.dart';
import '../services/live_session_service.dart';
import 'live_swipe_watch_screen.dart';
import 'live_watch_screen.dart';
import 'go_live_setup_screen.dart';
import '../../auth/user_role.dart';

/// Live Feed Screen - The main discovery hub for WeAfrica Live
/// 
/// Layout:
/// ┌──────────────────────────────┐
/// │ WeAfrica LIVE        🔍  +   │
/// │ Discover African creators    │
/// ├──────────────────────────────┤
/// │ [Live Now] [Battles] [Events]│
/// ├──────────────────────────────┤
/// │ 🔥 Featured Battle Card      │
/// ├──────────────────────────────┤
/// │ Solo Lives                   │
/// │ [card] [card] [card]         │
/// ├──────────────────────────────┤
/// │ Upcoming Battles             │
/// │ [battle card]                │
/// ├──────────────────────────────┤
/// │ Top DJs / Artists Live       │
/// │ [creator card]               │
/// └──────────────────────────────┘
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen>
    with SingleTickerProviderStateMixin {
  final LiveFeedDiscoverService _service = LiveFeedDiscoverService();
  
  // Data states
  List<Map<String, dynamic>> _liveStreams = [];
  List<Map<String, dynamic>> _battles = [];
  List<Map<String, dynamic>> _upcomingBattles = [];
  List<Map<String, dynamic>> _topCreators = [];
  
  bool _loading = true;
  String? _error;
  int _selectedTab = 0; // 0 = Live Now, 1 = Battles, 2 = Upcoming
  
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.fetchLiveNow(limit: 40),
        _service.fetchActiveBattles(limit: 10),
        _service.fetchUpcomingBattles(limit: 10),
        _service.fetchTopCreators(limit: 10),
      ]);

      if (!mounted) return;
      
      setState(() {
        _liveStreams = results[0].where((m) => !_isInternalTestStream(m)).toList();
        _battles = results[1];
        _upcomingBattles = results[2];
        _topCreators = results[3];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Live right now.';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  bool _isInternalTestStream(Map<String, dynamic> row) {
    final text = '${row['host_name']} ${row['host_id']} ${row['channel_id']}'.toLowerCase();
    return text.contains('phase2') ||
        text.contains('verify') ||
        text.contains('post3000');
  }

  bool _isBattleStream(Map<String, dynamic> stream) {
    final channelId = _s(stream['channel_id']);
    if (channelId.startsWith('weafrica_battle_')) return true;
    if (stream['live_type'] == 'battle') return true;
    if (stream['mode'] == 'BATTLE_1v1') return true;
    return false;
  }

  String _s(dynamic v) => (v ?? '').toString().trim();
  
  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String? _resolveImageUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return v;
    try {
      return Supabase.instance.client.storage.from('thumbnails').getPublicUrl(v);
    } catch (_) {
      return null;
    }
  }

  void _navigateToGoLive() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to go live')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoLiveSetupScreen(
          role: UserRole.artist, // Default to artist, can be determined by profile
          hostId: user.uid,
          hostName: user.displayName ?? 'Artist',
        ),
      ),
    );
  }

  Future<void> _joinLive(Map<String, dynamic> stream) async {
    final channelId = _s(stream['channel_id']);
    if (channelId.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final viewerId = (user?.uid ?? 'guest');

    final isBattle = _isBattleStream(stream);
    final battleId = _s(stream['battle_id']).isNotEmpty 
        ? _s(stream['battle_id']) 
        : (channelId.startsWith('weafrica_battle_') 
            ? channelId.substring('weafrica_battle_'.length) 
            : null);

    final joinRes = await LiveSessionService().joinSession(
      channelId,
      viewerId,
      battleId: isBattle ? battleId : null,
    );
    
    final session = joinRes.data;
    if (session == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not join this live right now.'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    final agoraUid = _stableAgoraUid(viewerId);

    if (isBattle && battleId != null) {
      final battleRes = await BattleService().getBattle(session.id, battleId: battleId);
      final battle = battleRes.data;
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsumerBattleScreen(
            sessionId: session.id,
            liveId: session.liveId,
            battleId: battle?.id ?? battleId,
            competitor1Id: battle?.competitor1Id ?? _s(stream['host_id']),
            competitor2Id: battle?.competitor2Id ?? '',
            competitor1Name: battle?.competitor1Name ?? _s(stream['host_name']),
            competitor2Name: battle?.competitor2Name ?? 'Opponent',
            competitor1Type: battle?.competitor1Type ?? 'artist',
            competitor2Type: battle?.competitor2Type ?? 'artist',
            durationSeconds: battle?.timeRemaining ?? 1800,
            currentUserId: viewerId,
            currentUserName: (_s(user?.displayName).isNotEmpty ? _s(user?.displayName) : 'Viewer'),
            channelId: session.channelId,
            token: session.token,
            agoraUid: agoraUid,
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveWatchScreen(
          channelId: session.channelId,
          hostName: _s(stream['host_name']),
          streamId: _s(stream['id']),
        ),
      ),
    );
  }

  int _stableAgoraUid(String userId) {
    final h = userId.hashCode.abs();
    final uid = (h % 2000000000);
    return uid == 0 ? 1 : uid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: WeAfricaColors.gold,
        backgroundColor: Colors.black,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _buildHeader(),
            ),
            
            // Tab Bar
            SliverToBoxAdapter(
              child: _buildTabBar(),
            ),
            
            if (_loading && _liveStreams.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: WeAfricaColors.gold),
                ),
              )
            else if (_error != null && _liveStreams.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WeAfricaColors.gold,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Featured Battle (if any)
              if (_battles.isNotEmpty && _selectedTab != 2)
                SliverToBoxAdapter(
                  child: _buildFeaturedBattleCard(_battles.first),
                ),
              
              // Solo Lives Section
              if (_selectedTab == 0 && _liveStreams.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Solo Lives', _liveStreams.length),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildSoloLiveCard(_liveStreams[index]),
                      childCount: _liveStreams.length,
                    ),
                  ),
                ),
              ],
              
              // Battles Section
              if (_selectedTab == 1 && _battles.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Live Battles', _battles.length),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildBattleCard(_battles[index]),
                      childCount: _battles.length,
                    ),
                  ),
                ),
              ],
              
              // Upcoming Battles Section
              if (_selectedTab == 2 && _upcomingBattles.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Upcoming Battles', _upcomingBattles.length),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildUpcomingBattleCard(_upcomingBattles[index]),
                      childCount: _upcomingBattles.length,
                    ),
                  ),
                ),
              ],
              
              // Top Creators Section
              if (_topCreators.isNotEmpty && _selectedTab == 0) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Top DJs / Artists', _topCreators.length),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _topCreators.length,
                      itemBuilder: (context, index) => _buildCreatorCard(_topCreators[index]),
                    ),
                  ),
                ),
              ],
              
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          ],
        ),
      ),
      floatingActionButton: _buildGoLiveButton(),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: WeAfricaColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'WeAfrica LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Discover African creators',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                // Search functionality
              },
              icon: const Icon(Icons.search, color: Colors.white),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _navigateToGoLive,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [WeAfricaColors.gold, Color(0xFFD4A574)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.black,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['Live Now', 'Battles', 'Events'];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: List.generate(tabs.length, (index) {
            final isSelected = _selectedTab == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? WeAfricaColors.gold.withValues(alpha: 0.2) 
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: isSelected
                        ? Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      tabs[index],
                      style: TextStyle(
                        color: isSelected ? WeAfricaColors.gold : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Featured Battle Card
  /// Big wide card with dark glass background
  /// Artist A image left, Artist B image right, VS badge in center
  Widget _buildFeaturedBattleCard(Map<String, dynamic> battle) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => _joinLive(battle),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E),
                Colors.black.withValues(alpha: 0.8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: WeAfricaColors.gold.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background images
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                      child: _buildBattleArtistImage(
                        _resolveImageUrl(battle['competitor1_image']),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                      child: _buildBattleArtistImage(
                        _resolveImageUrl(battle['competitor2_image']),
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ),
                ],
              ),
              
              // VS Badge
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [WeAfricaColors.gold, Color(0xFFD4A574)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: WeAfricaColors.gold.withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Live badge
              Positioned(
                top: 12,
                left: 12,
                child: _LiveBadge(pulse: _pulse),
              ),
              
              // Viewer count
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _formatNumber(_asInt(battle['viewer_count'])),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Join button
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [WeAfricaColors.error, Color(0xFFD32F2F)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: WeAfricaColors.error.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Text(
                      'JOIN BATTLE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBattleArtistImage(String? imageUrl, {required Alignment alignment}) {
    return Container(
      decoration: BoxDecoration(
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
                alignment: alignment,
              )
            : null,
        gradient: imageUrl == null
            ? LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.3),
                  Colors.grey.withValues(alpha: 0.1),
                ],
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: alignment == Alignment.centerLeft 
                ? Alignment.centerRight 
                : Alignment.centerLeft,
            end: alignment,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
          ),
        ),
      ),
    );
  }

  /// Solo Live Card
  /// Vertical card with creator live thumbnail
  Widget _buildSoloLiveCard(Map<String, dynamic> stream) {
    final thumb = _resolveImageUrl(stream['thumbnail_url']);
    
    return GestureDetector(
      onTap: () => _joinLive(stream),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black,
          image: thumb != null
              ? DecorationImage(
                  image: NetworkImage(thumb),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Stack(
          children: [
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            
            // LIVE badge
            Positioned(
              top: 8,
              left: 8,
              child: _LiveBadge(pulse: _pulse),
            ),
            
            // Country flag (if available)
            if (stream['country_code'] != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getFlagEmoji(stream['country_code']),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            
            // Info at bottom
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _s(stream['host_name']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (stream['category'] != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: WeAfricaColors.gold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _s(stream['category']),
                            style: const TextStyle(
                              color: WeAfricaColors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.visibility,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatNumber(_asInt(stream['viewer_count'])),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Battle Card for battles list
  Widget _buildBattleCard(Map<String, dynamic> battle) {
    return GestureDetector(
      onTap: () => _joinLive(battle),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            // Competitor 1
            Expanded(
              child: _buildCompetitorInfo(
                name: _s(battle['competitor1_name']),
                image: _resolveImageUrl(battle['competitor1_image']),
                score: _asInt(battle['competitor1_score']),
              ),
            ),
            
            // VS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: WeAfricaColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'VS',
                style: TextStyle(
                  color: WeAfricaColors.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            
            // Competitor 2
            Expanded(
              child: _buildCompetitorInfo(
                name: _s(battle['competitor2_name']),
                image: _resolveImageUrl(battle['competitor2_image']),
                score: _asInt(battle['competitor2_score']),
                isRight: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetitorInfo({
    required String name,
    String? image,
    required int score,
    bool isRight = false,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isRight) ...[
          _buildAvatar(image, size: 40),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.isEmpty ? 'TBD' : name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$score pts',
                style: TextStyle(
                  color: WeAfricaColors.gold.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (isRight) ...[
          const SizedBox(width: 10),
          _buildAvatar(image, size: 40),
        ],
      ],
    );
    
    return isRight 
        ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [content])
        : content;
  }

  Widget _buildAvatar(String? imageUrl, {double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.withValues(alpha: 0.3),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              )
            : null,
        border: Border.all(
          color: WeAfricaColors.gold.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: imageUrl == null
          ? Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5), size: size * 0.5)
          : null,
    );
  }

  /// Upcoming Battle Card
  Widget _buildUpcomingBattleCard(Map<String, dynamic> battle) {
    final scheduledAt = battle['scheduled_at'] != null
        ? DateTime.tryParse(battle['scheduled_at'])
        : null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_s(battle['competitor1_name'])} vs ${_s(battle['competitor2_name'])}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (battle['prize'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: WeAfricaColors.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🏆 ${_s(battle['prize'])}',
                    style: const TextStyle(
                      color: WeAfricaColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.schedule,
                color: Colors.white.withValues(alpha: 0.6),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                scheduledAt != null
                    ? _formatTimeUntil(scheduledAt)
                    : 'Coming soon',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  // Notify me functionality
                },
                icon: const Icon(Icons.notifications_outlined, size: 16),
                label: const Text('Notify me'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WeAfricaColors.gold,
                  side: BorderSide(color: WeAfricaColors.gold.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Creator Card (horizontal scroll)
  Widget _buildCreatorCard(Map<String, dynamic> creator) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            children: [
              _buildAvatar(_resolveImageUrl(creator['avatar_url']), size: 70),
              if (creator['is_live'] == true)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: WeAfricaColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _s(creator['name']),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            _s(creator['genre']),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {},
            child: const Text(
              'See all',
              style: TextStyle(
                color: WeAfricaColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoLiveButton() {
    return FloatingActionButton.extended(
      onPressed: _navigateToGoLive,
      backgroundColor: WeAfricaColors.error,
      icon: const Icon(Icons.videocam, color: Colors.white),
      label: const Text(
        'GO LIVE',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _getFlagEmoji(String? countryCode) {
    if (countryCode == null || countryCode.length != 2) return '🌍';
    final code = countryCode.toUpperCase();
    return String.fromCharCode(code.codeUnitAt(0) + 0x1F1E6 - 65) +
           String.fromCharCode(code.codeUnitAt(1) + 0x1F1E6 - 65);
  }

  String _formatTimeUntil(DateTime scheduledAt) {
    final now = DateTime.now();
    final difference = scheduledAt.difference(now);
    
    if (difference.isNegative) return 'Starting now';
    if (difference.inDays > 0) return '${difference.inDays}d ${difference.inHours % 24}h';
    if (difference.inHours > 0) return '${difference.inHours}h ${difference.inMinutes % 60}m';
    return '${difference.inMinutes}m';
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WeAfricaColors.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: pulse,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}