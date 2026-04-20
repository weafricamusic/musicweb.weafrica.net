import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:glass_kit/glass_kit.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/constants/weafrica_power_voice.dart';
import '../../app/widgets/gold_button.dart';
import '../artist_dashboard/screens/artist_profile_settings_screen.dart';
import '../auth/auth_actions.dart';
import '../auth/user_role.dart';
import '../auth/user_role_intent_store.dart';
import '../auth/user_role_resolver.dart';
import '../creator/creator_dashboard_screen.dart';
import '../creator/widgets/creator_tier_badge.dart';
import '../creator/services/creator_stats_service.dart';
import '../wallet/widgets/wallet_preview_card.dart';
import '../wallet/wallet_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../dj_dashboard/screens/dj_profile_screen.dart';
import '../library/screens/library_tab.dart';
import '../settings/role_based_settings_screen.dart';
import '../../services/creator_finance_api.dart';
import '../subscriptions/subscriptions_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.roleOverride});

  final UserRole? roleOverride;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFF2D572);
  
  late AnimationController _avatarController;
  late Animation<double> _avatarAnimation;
  late AnimationController _pulseController;
  
  CreatorStats? _creatorStats;
  bool _loadingStats = false;
  int? _walletBalance;
  bool _walletLoading = false;

  @override
  void initState() {
    super.initState();

    // Keep subscription state fresh when opening Profile.
    SubscriptionsController.instance.initialize();
    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(SubscriptionsController.instance.refreshMe());
    }

    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    _avatarAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _avatarController, curve: Curves.easeInOut),
    );
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadWalletBalance();
    _loadCreatorStats();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadCreatorStats() async {
    final role = widget.roleOverride ?? await UserRoleResolver.resolveCurrentUser();
    if (role == UserRole.artist || role == UserRole.dj) {
      setState(() => _loadingStats = true);
      try {
        final stats = await CreatorStatsService().getStats(role: role);
        if (mounted) {
          setState(() {
            _creatorStats = stats;
            _loadingStats = false;
          });
        }
      } catch (e) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Future<void> _loadWalletBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_walletLoading) return;

    setState(() => _walletLoading = true);
    try {
      final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
      if (!mounted) return;
      setState(() {
        _walletBalance = summary.coinBalance.round();
      });
    } catch (_) {
      // Best-effort; keep wallet balance unknown.
    } finally {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  String _getInitials(String? displayName, String? email) {
    if (displayName != null && displayName.isNotEmpty) {
      final parts = displayName.split(' ');
      if (parts.length > 1) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName[0].toUpperCase();
    }
    if (email != null && email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    final email = user?.email ?? '';
    final avatarUrl = (user?.photoURL ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_gold, _goldLight],
          ).createShader(bounds),
          child: const Text(
            'PROFILE',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _gold.withAlpha(26),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withAlpha(77)),
            ),
            child: IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RoleBasedSettingsScreen(roleOverride: widget.roleOverride),
                  ),
                );
              },
              icon: const Icon(Icons.settings, color: _gold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 100, 16, 32),
        children: [
          // Profile Header with Glass Card
          GlassContainer(
            width: double.infinity,
            height: 120,
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1A1A28).withAlpha(128),
                const Color(0xFF12121C).withAlpha(77),
              ],
            ),
            borderColor: _gold.withAlpha(77),
            blur: 15,
            child: Row(
              children: [
                // Animated Avatar
                AnimatedBuilder(
                  animation: _avatarAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _avatarAnimation.value,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_gold, _goldLight],
                          ),
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withAlpha(77),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFF1A1A28),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    _getInitials(displayName, email),
                                    style: const TextStyle(
                                      color: _gold,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                
                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName.isEmpty ? 'Music Lover' : displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Role badge will be added by FutureBuilder
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isEmpty ? 'No email' : email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(128),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Wallet Preview Card (if logged in)
          if (user != null) ...[
            if (_walletLoading)
              Shimmer.fromColors(
                baseColor: Colors.white.withAlpha(26),
                highlightColor: Colors.white.withAlpha(51),
                child: Container(
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              )
            else
              WalletPreviewCard(
                balance: _walletBalance,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WalletScreen(roleOverride: widget.roleOverride),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
          ],

          // Role-based Content
          FutureBuilder<UserRole>(
            future: widget.roleOverride != null
                ? Future.value(widget.roleOverride!)
                : UserRoleResolver.resolveCurrentUser(),
            builder: (context, snap) {
              final role = snap.data ?? UserRole.consumer;
              final isCreator = role == UserRole.artist || role == UserRole.dj;
              final isLoading = snap.connectionState == ConnectionState.waiting;

              if (isLoading) {
                return Shimmer.fromColors(
                  baseColor: Colors.white.withAlpha(26),
                  highlightColor: Colors.white.withAlpha(51),
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  // Role Indicator with Tier
                  GlassContainer(
                    width: double.infinity,
                    height: 84,
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        _gold.withAlpha(26),
                        Colors.transparent,
                      ],
                    ),
                    borderColor: _gold.withAlpha(51),
                    blur: 10,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _gold.withAlpha(51),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isCreator ? Icons.star : Icons.person,
                            color: _gold,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isCreator
                                    ? 'You have creator access'
                                    : 'Enjoy the music',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withAlpha(128),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isCreator) const CreatorTierBadge(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Creator Stats Preview
                  if (isCreator) _buildCreatorStatsPreview(),

                  const SizedBox(height: 16),

                  // Creator Studio Button
                  if (isCreator) ...[
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 0.98 + (_pulseController.value * 0.04),
                          child: GlassContainer(
                            width: double.infinity,
                            height: 56,
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              colors: [
                                _gold.withAlpha(77),
                                _gold.withAlpha(26),
                              ],
                            ),
                            borderColor: _gold,
                            blur: 15,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openStudio(context, role),
                                borderRadius: BorderRadius.circular(28),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.dashboard, color: _gold),
                                    const SizedBox(width: 8),
                                    Text(
                                      WeAfricaPowerVoice.ctaOpenCreatorStudio.toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: _gold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action Buttons
                  _buildActionButton(
                    icon: Icons.edit,
                    label: 'EDIT PROFILE',
                    onTap: () async {
                      UserRole intent;
                      try {
                        intent = await UserRoleIntentStore.getRole();
                      } catch (_) {
                        intent = UserRole.consumer;
                      }

                      // Listener mode must stay in consumer profile edit UI
                      // even when the account itelf is creator-enabled.
                      if (!context.mounted) return;
                      if (intent == UserRole.consumer) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                        );
                        return;
                      }

                      UserRole resolved;
                      try {
                        resolved = await UserRoleResolver.resolveCurrentUser();
                      } catch (_) {
                        resolved = UserRole.consumer;
                      }
                      if (!context.mounted) return;

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) {
                            if (resolved == UserRole.artist) {
                              return const ArtistProfileSettingsScreen();
                            }
                            if (resolved == UserRole.dj) {
                              return const DjProfileScreen();
                            }
                            return const EditProfileScreen();
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildActionButton(
                    icon: Icons.settings,
                    label: 'SETTINGS',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoleBasedSettingsScreen(roleOverride: widget.roleOverride),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildActionButton(
                    icon: Icons.favorite,
                    label: 'LIKED SONGS',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LibraryTab(initialFilter: 'LIKED'),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildActionButton(
                    icon: Icons.download,
                    label: 'DOWNLOADS',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LibraryTab(initialFilter: 'DOWNLOADED'),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Sign Out Button (with different style)
                  InkWell(
                    onTap: () => _showSignOutDialog(context),
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.red.withAlpha(77),
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: Colors.red.withAlpha(204)),
                          const SizedBox(width: 8),
                          Text(
                            'SIGN OUT',
                            style: TextStyle(
                              color: Colors.red.withAlpha(204),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorStatsPreview() {
    if (_loadingStats) {
      return Shimmer.fromColors(
        baseColor: Colors.white.withAlpha(26),
        highlightColor: Colors.white.withAlpha(51),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    final stats = _creatorStats;
    final followersText = (stats?.followers == null) ? '—' : _formatCount(stats!.followers!);
    final streamsText = (stats?.streams == null) ? '—' : _formatCount(stats!.streams!);
    final earningsText = (stats?.earningsCoins == null)
      ? '💎 —'
      : '💎 ${_formatCount(stats!.earningsCoins!)}';

    return GlassContainer(
      width: double.infinity,
      height: 88,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        colors: [
          _gold.withAlpha(26),
          Colors.transparent,
        ],
      ),
      borderColor: _gold.withAlpha(51),
      blur: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('FOLLOWERS', followersText),
          _buildStatItem('STREAMS', streamsText),
          _buildStatItem('EARNINGS', earningsText),
        ],
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: _gold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withAlpha(128),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A28).withAlpha(128),
              const Color(0xFF12121C).withAlpha(77),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _gold.withAlpha(51),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _gold, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: _gold, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          width: double.infinity,
          height: 260,
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A28),
              const Color(0xFF12121C),
            ],
          ),
          borderColor: _gold.withAlpha(77),
          blur: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(26),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withAlpha(77)),
                ),
                child: const Icon(
                  Icons.logout,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'SIGN OUT',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to sign out?',
                style: TextStyle(
                  color: Colors.white.withAlpha(179),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GoldButton(
                      onPressed: () {
                        Navigator.pop(context);
                        AuthActions.signOut();
                      },
                      label: 'SIGN OUT',
                      icon: Icons.logout,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStudio(BuildContext context, UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatorDashboardScreen(role: role),
      ),
    );
  }
}