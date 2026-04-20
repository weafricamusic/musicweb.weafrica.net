import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../ai_creator/ai_creator_screen.dart';
import '../artist_dashboard/screens/artist_dashboard_screen.dart';
import '../auth/auth_actions.dart';
import '../auth/user_role.dart';
import '../dj_dashboard/screens/dj_dashboard_screen.dart';
import '../creator_dashboard/providers/creator_dashboard_provider.dart';
import 'creator_upload_screen.dart';
import 'upload_video_screen.dart';

class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CreatorDashboardProvider>().loadDashboardData();
    });
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CreatorDashboardProvider>();
    final isArtist = widget.role == UserRole.artist;
    final isDj = widget.role == UserRole.dj;

    final artistName = (provider.artist?['stage_name'] ??
            provider.artist?['display_name'] ??
            provider.artist?['name'] ??
            provider.artist?['artist_name'])
        ?.toString()
        .trim();
    final titleName = (artistName != null && artistName.isNotEmpty) ? artistName : '${widget.role.label} Studio';

    if (provider.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceDark,
          elevation: 0,
          title: Text(titleName),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.error != null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceDark,
          elevation: 0,
          title: Text(titleName),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 44, color: AppColors.error),
                const SizedBox(height: 12),
                Text(
                  'Error loading dashboard',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => provider.loadDashboardData(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            Text(
              titleName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          // Notifications
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {},
                color: AppColors.textSecondary,
              ),
              if (provider.unreadMessages > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.live,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${provider.unreadMessages}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Profile
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.border),
            ),
            child: IconButton(
              icon: const Icon(Icons.person, size: 20),
              onPressed: () => AuthActions.signOut(),
              color: AppColors.brandGold,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadDashboardData(),
        color: AppColors.brandGold,
        backgroundColor: AppColors.surface2,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Quick Stats Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatPreview(
                    label: 'STREAMS',
                    value: _formatNumber((provider.stats?['total_streams'] as num?)?.toInt() ?? 0),
                    icon: Icons.play_circle,
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: AppColors.border,
                  ),
                  _StatPreview(
                    label: 'EARNED',
                    value: '₵${_formatNumber((provider.earnings['total'] as num?)?.toInt() ?? 0)}',
                    icon: Icons.monetization_on,
                  ),
                  Container(
                    height: 30,
                    width: 1,
                    color: AppColors.border,
                  ),
                  _StatPreview(
                    label: 'BATTLES',
                    value: '${(provider.stats?['total_battles'] as num?)?.toInt() ?? 0}',
                    icon: Icons.sports_mma,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Quick Actions Row
            Row(
              children: [
                Expanded(
                  child: _QuickActionChip(
                    icon: Icons.music_note,
                    label: 'UPLOAD\nMUSIC',
                    onTap: () => _openPage(
                      context,
                      CreatorUploadScreen(creatorIntent: widget.role),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionChip(
                    icon: Icons.video_library,
                    label: 'UPLOAD\nVIDEO',
                    onTap: () => _openPage(
                      context,
                      UploadVideoScreen(creatorIntent: widget.role),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionChip(
                    icon: Icons.sports_mma,
                    label: 'CREATE\nBATTLE',
                    onTap: () {},
                    badge: provider.pendingBattles > 0 ? '${provider.pendingBattles}' : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Section Title
            Text(
              'YOUR STUDIOS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 12),

            // Studio Cards Grid
            if (isArtist) ...[
              _buildArtistStudioCard(context),
            ] else ...[
              _buildCreatorStudioCard(context),
              const SizedBox(height: 12),
              if (isDj) _buildDjStudioCard(context),
              _buildUploadStudioCard(context),
            ],

            const SizedBox(height: 20),

            // Active Battles Preview (if any)
            if (provider.activeBattles.isNotEmpty) ...[
              _buildActiveBattlesPreview(provider),
              const SizedBox(height: 20),
            ],

            // Recent Activity Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.history,
                        size: 16,
                        color: AppColors.brandGold,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RECENT ACTIVITY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (provider.activeBattles.isNotEmpty)
                    _ActivityItem(
                      icon: Icons.sports_mma,
                      color: AppColors.live,
                      text: '${provider.activeBattles.length} active battle${provider.activeBattles.length == 1 ? '' : 's'}',
                      time: 'Live now',
                    ),

                  if (provider.activeBattles.isNotEmpty) const Divider(height: 16, color: AppColors.border),

                  if (provider.unreadMessages > 0)
                    _ActivityItem(
                      icon: Icons.message,
                      color: AppColors.brandGold,
                      text: '${provider.unreadMessages} new fan message${provider.unreadMessages == 1 ? '' : 's'}',
                      time: 'Recent',
                    ),

                  if (provider.unreadMessages > 0) const Divider(height: 16, color: AppColors.border),

                  ...provider.recentMessages.take(2).map((msg) {
                    final sender = (msg['sender_name'] ?? msg['from'] ?? msg['email'] ?? 'Fan').toString();
                    final body = (msg['message'] ?? msg['body'] ?? msg['content'] ?? '').toString();
                    final createdAt = (msg['created_at'] ?? msg['createdAt'])?.toString();

                    return Column(
                      children: [
                        _ActivityItem(
                          icon: Icons.person,
                          color: AppColors.info,
                          text: '$sender: $body',
                          time: _formatTime(createdAt),
                        ),
                        const Divider(height: 16, color: AppColors.border),
                      ],
                    );
                  }),

                  if (((provider.earnings['total'] as num?) ?? 0) > 0)
                    _ActivityItem(
                      icon: Icons.emoji_events,
                      color: AppColors.success,
                      text: 'Total earnings: ₵${_formatNumber((provider.earnings['total'] as num?)?.toInt() ?? 0)}',
                      time: 'All time',
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uploading requires an eligible creator account and permissions.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBattlesPreview(CreatorDashboardProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.live,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ACTIVE BATTLES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...provider.activeBattles.take(2).map((battle) {
            final status = (battle['status'] ?? 'live').toString();
            final title = (battle['title'] ?? '').toString().trim();
            final label = title.isNotEmpty ? title : 'Live Battle';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: status.toLowerCase() == 'live'
                          ? AppColors.live.withValues(alpha: 0.1)
                          : AppColors.pending.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      status.toLowerCase() == 'live' ? Icons.circle : Icons.access_time,
                      color: status.toLowerCase() == 'live' ? AppColors.live : AppColors.pending,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: status.toLowerCase() == 'live' ? AppColors.live : AppColors.pending,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.textMuted,
                    size: 16,
                  ),
                ],
              ),
            );
          }),
          if (provider.activeBattles.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '+${provider.activeBattles.length - 2} more battles',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArtistStudioCard(BuildContext context) {
    return _StudioCard(
      icon: Icons.mic,
      title: 'ARTIST STUDIO',
      subtitle: 'Full artist dashboard with battles, music, and earnings',
      features: const ['Music Empire', 'War Room', 'The Nation', 'Earnings'],
      accent: AppColors.brandGold,
      onTap: () => _openPage(context, const ArtistDashboardScreen()),
    );
  }

  Widget _buildCreatorStudioCard(BuildContext context) {
    return _StudioCard(
      icon: Icons.auto_awesome,
      title: 'AI CREATOR STUDIO',
      subtitle: 'Generate AI music and manage your creations',
      features: const ['AI Tracks', 'Voice Models', 'Samples', 'Royalties'],
      accent: AppColors.brandPurple,
      onTap: () => _openPage(context, AiCreatorScreen(role: widget.role)),
    );
  }

  Widget _buildDjStudioCard(BuildContext context) {
    return _StudioCard(
      icon: Icons.graphic_eq,
      title: 'DJ STUDIO',
      subtitle: 'Mix, battle, and manage your DJ career',
      features: const ['Mixes', 'Live Sets', 'Battles', 'Crowd Analytics'],
      accent: AppColors.brandGold,
      onTap: () => _openPage(context, const DjDashboardScreen()),
    );
  }

  Widget _buildUploadStudioCard(BuildContext context) {
    final isDj = widget.role == UserRole.dj;
    
    return _StudioCard(
      icon: Icons.cloud_upload,
      title: isDj ? 'CONTENT STUDIO' : 'UPLOAD STUDIO',
      subtitle: isDj
          ? 'Upload mixes, sets, and videos'
          : 'Upload music, videos, and create albums',
      features: isDj
          ? const ['Mixes', 'Sets', 'Videos']
          : const ['Singles', 'Albums', 'Videos'],
      accent: AppColors.brandPink,
      onTap: () => _openPage(
        context,
        isDj
            ? const CreatorUploadScreen(creatorIntent: UserRole.dj)
            : const UploadVideoScreen(),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null || timestamp.trim().isEmpty) return 'Recently';
    final time = DateTime.tryParse(timestamp);
    if (time == null) return 'Recently';
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${difference.inDays ~/ 7}w ago';
  }
}

// Stat Preview Widget
class _StatPreview extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatPreview({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.brandGold),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// Quick Action Chip
class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(icon, color: AppColors.brandGold, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.live,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Studio Card
class _StudioCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> features;
  final Color accent;
  final VoidCallback onTap;

  const _StudioCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: features.map((feature) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  feature,
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// Activity Item
class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 12),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}