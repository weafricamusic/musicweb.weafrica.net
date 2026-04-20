import 'package:flutter/material.dart';
import '../models/artist_dashboard_models.dart';

class ArtistProfileMainView extends StatelessWidget {
  const ArtistProfileMainView({
    super.key,
    required this.dashboardData,
    required this.onEditProfile,
  });

  final ArtistDashboardHomeData dashboardData;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                SizedBox(height: 12),
                Text(
                  'Artist Profile',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Tracks',
                  value: dashboardData.recentSongs.length.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'Followers',
                  value: _formatNumber(dashboardData.followersCount),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'Plays',
                  value: _formatNumber(dashboardData.totalPlays),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onEditProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
