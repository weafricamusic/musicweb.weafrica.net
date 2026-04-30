import 'package:flutter/material.dart';

import '../../wallet/services/gift_service.dart';

/// WeAfrica Leaderboard Screen
/// 
/// Shows Top Supporters, Top Artists, and Battle Winners
/// Drives competition and spending
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFD4AF37),
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Top Artists'),
            Tab(text: 'Top Supporters'),
            Tab(text: 'Battle Winners'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTopArtistsTab(),
          _buildTopSupportersTab(),
          _buildBattleWinnersTab(),
        ],
      ),
    );
  }

  Widget _buildTopArtistsTab() {
    // Mock data - replace with actual API call
    final artists = [
      {'name': 'Burna Boy', 'earnings': 125000, 'gifts': 5400, 'avatar': '🔥'},
      {'name': 'WizKid', 'earnings': 98000, 'gifts': 4200, 'avatar': '🌟'},
      {'name': 'Davido', 'earnings': 87000, 'gifts': 3800, 'avatar': '💎'},
      {'name': 'Tiwa Savage', 'earnings': 76000, 'gifts': 3200, 'avatar': '👑'},
      {'name': 'Diamond Platnumz', 'earnings': 65000, 'gifts': 2800, 'avatar': '💰'},
      {'name': 'Yemi Alade', 'earnings': 54000, 'gifts': 2300, 'avatar': '🎤'},
      {'name': 'Sauti Sol', 'earnings': 43000, 'gifts': 1900, 'avatar': '🎸'},
      {'name': 'Master KG', 'earnings': 38000, 'gifts': 1600, 'avatar': '🎹'},
    ];

    return _buildLeaderboardList(
      items: artists,
      rankBuilder: (index) => _buildRankBadge(index),
      titleBuilder: (item) => item['name'] as String,
      subtitleBuilder: (item) => '\$${(item['earnings'] as int).toStringAsFixed(0)} earned',
      trailingBuilder: (item) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard, color: Color(0xFFD4AF37), size: 16),
          const SizedBox(width: 4),
          Text(
            '${item['gifts']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSupportersTab() {
    // Mock data - replace with actual API call
    final supporters = [
      {'name': 'AfroKing2024', 'spent': 45000, 'gifts': 890, 'avatar': '🦁'},
      {'name': 'MusicLover', 'spent': 38000, 'gifts': 720, 'avatar': '🎵'},
      {'name': 'SuperFan', 'spent': 32000, 'gifts': 650, 'avatar': '⭐'},
      {'name': 'NaijaBoy', 'spent': 28000, 'gifts': 540, 'avatar': '🇳🇬'},
      {'name': 'MzansiQueen', 'spent': 24000, 'gifts': 480, 'avatar': '🇿🇦'},
      {'name': 'GhanaFinest', 'spent': 21000, 'gifts': 420, 'avatar': '🇬🇭'},
      {'name': 'KenyaPride', 'spent': 18000, 'gifts': 360, 'avatar': '🇰🇪'},
      {'name': 'AfricanKing', 'spent': 15000, 'gifts': 300, 'avatar': '👑'},
    ];

    return _buildLeaderboardList(
      items: supporters,
      rankBuilder: (index) => _buildRankBadge(index),
      titleBuilder: (item) => item['name'] as String,
      subtitleBuilder: (item) => '\$${(item['spent'] as int).toStringAsFixed(0)} spent',
      trailingBuilder: (item) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${item['gifts']} gifts',
          style: const TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBattleWinnersTab() {
    // Mock data - replace with actual API call
    final winners = [
      {
        'name': 'Burna Boy',
        'battle': 'Afrobeat Clash 2024',
        'prize': 50000,
        'wins': 12,
        'avatar': '🔥',
      },
      {
        'name': 'Diamond Platnumz',
        'battle': 'Bongo Flava Finale',
        'prize': 35000,
        'wins': 8,
        'avatar': '💎',
      },
      {
        'name': 'Sauti Sol',
        'battle': 'East African Showdown',
        'prize': 28000,
        'wins': 6,
        'avatar': '🎸',
      },
      {
        'name': 'Yemi Alade',
        'battle': 'Queen of Afro Pop',
        'prize': 22000,
        'wins': 5,
        'avatar': '👑',
      },
      {
        'name': 'Master KG',
        'battle': 'Jerusalema Challenge',
        'prize': 18000,
        'wins': 4,
        'avatar': '🎹',
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: winners.length,
      itemBuilder: (context, index) {
        final winner = winners[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: index == 0
                ? const LinearGradient(
                    colors: [Color(0xFF2A1A0A), Color(0xFF1A1A1A)],
                  )
                : null,
            color: index == 0 ? null : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: index == 0 ? const Color(0xFFD4AF37) : const Color(0xFF333333),
              width: index == 0 ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _buildRankBadge(index),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          winner['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          winner['avatar'] as String,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      winner['battle'] as String,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '\$${(winner['prize'] as int).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${winner['wins']} wins',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (index == 0)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Color(0xFF0A0A0A),
                    size: 24,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaderboardList({
    required List<Map<String, dynamic>> items,
    required Widget Function(int index) rankBuilder,
    required String Function(Map<String, dynamic> item) titleBuilder,
    required String Function(Map<String, dynamic> item) subtitleBuilder,
    required Widget Function(Map<String, dynamic> item) trailingBuilder,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isTop3 = index < 3;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isTop3
                ? LinearGradient(
                    colors: [
                      const Color(0xFFD4AF37).withValues(alpha: 0.1),
                      const Color(0xFF1A1A1A),
                    ],
                  )
                : null,
            color: isTop3 ? null : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTop3
                  ? const Color(0xFFD4AF37).withValues(alpha: 0.3)
                  : const Color(0xFF333333),
            ),
          ),
          child: Row(
            children: [
              rankBuilder(index),
              const SizedBox(width: 16),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    item['avatar'] as String,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleBuilder(item),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleBuilder(item),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              trailingBuilder(item),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRankBadge(int index) {
    final colors = [
      const Color(0xFFFFD700), // Gold
      const Color(0xFFC0C0C0), // Silver
      const Color(0xFFCD7F32), // Bronze
    ];

    if (index < 3) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors[index].withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: colors[index], width: 2),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: colors[index],
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}