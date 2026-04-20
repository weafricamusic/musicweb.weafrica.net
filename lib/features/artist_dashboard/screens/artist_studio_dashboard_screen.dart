import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/config/debug_flags.dart';
import '../../../debug_tier_mapper.dart';
import '../../../app/widgets/auto_artwork.dart';
import '../../../core/navigation/left_menu.dart';
import '../../../core/navigation/menu_items.dart';
import '../../../data/repositories/artist_repository.dart';
import '../../../data/repositories/battle_repository.dart';
import '../models/artist_dashboard_models.dart';
import '../services/artist_dashboard_service.dart';
import '../services/artist_identity_service.dart';
import '../models/artist_subscription_tier.dart';
import '../../player/playback_controller.dart';
import '../../player/player_routes.dart';
import '../../auth/user_role.dart';
import '../../live/screens/go_live_setup_screen.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../../subscriptions/subscriptions_controller.dart';
import 'artist_profile_settings_screen.dart';
import 'artist_earnings_screen.dart';
import 'artist_content_screen.dart';
import 'artist_profile_screen.dart';
import 'artist_go_live_hub_screen.dart';
import 'artist_upload_hub_screen.dart';

const Color _kStudioSurface = Color(0xFF1A1A1E);
const Color _kStudioSurfaceAlt = Color(0xFF141416);
const Color _kStudioBorder = Color(0xFF2C2C30);
const Color _kStudioMutedText = Color(0xFF9B9B9B);

class _StudioCard extends StatelessWidget {
  const _StudioCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(18));

    final ink = Ink(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? _kStudioSurface : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? _kStudioBorder),
      ),
      child: child,
    );

    return Material(
      color: Colors.transparent,
      child: onTap == null
          ? ink
          : InkWell(onTap: onTap, borderRadius: radius, child: ink),
    );
  }
}

class _StudioMetricCard extends StatelessWidget {
  const _StudioMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tooltip,
  });

  final String label;
  final String value;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: tooltip,
      child: _StudioCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _kStudioMutedText,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.info_outline, size: 16, color: _kStudioMutedText),
          ],
        ),
      ),
    );
  }
}

class _StudioValueText extends StatelessWidget {
  const _StudioValueText({required this.value, this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effective =
        style ??
        Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900) ??
        const TextStyle(fontWeight: FontWeight.w900);

    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effective,
    );
  }
}

class _StudioNetworkImage extends StatelessWidget {
  const _StudioNetworkImage({
    required this.imageUrl,
    required this.seed,
    required this.icon,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final String imageUrl;
  final String seed;
  final IconData icon;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final hasUrl = url.startsWith('http://') || url.startsWith('https://');

    final placeholder = AutoArtwork(seed: seed, icon: icon);

    final image = hasUrl
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (context, _) => placeholder,
            errorWidget: (context, url, error) => placeholder,
          )
        : placeholder;

    return ClipRRect(borderRadius: borderRadius, child: image);
  }
}

class ArtistStudioDashboardScreen extends StatefulWidget {
  const ArtistStudioDashboardScreen({super.key});

  @override
  State<ArtistStudioDashboardScreen> createState() =>
      _ArtistStudioDashboardScreenState();
}

class _ArtistStudioDashboardScreenState
    extends State<ArtistStudioDashboardScreen> {
  final ArtistDashboardService _service = ArtistDashboardService();
  late Future<ArtistDashboardHomeData> _future;
  DateTime? _lastUpdated;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Keep subscription state available for tier-aware UI and upgrade flows.
    SubscriptionsController.instance.initialize();
    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(SubscriptionsController.instance.refreshMe());
    }
    _future = _service.loadHome();
    _trackFuture(_future);
  }

  void _trackFuture(Future<ArtistDashboardHomeData> future) {
    future
        .then((_) {
          if (!mounted) return;
          setState(() {
            _lastUpdated = DateTime.now();
            _isRefreshing = false;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _isRefreshing = false;
          });
        });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _future = _service.loadHome();
      _trackFuture(_future);
    });

    unawaited(SubscriptionsController.instance.refreshMe());

    try {
      await _future;
    } catch (_) {
      // Best-effort; the FutureBuilder will show the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName = (user?.displayName ?? '').trim();
    final artistName = displayName.isNotEmpty ? displayName : 'Artist';

    final email = (user?.email ?? '').trim();
    final artistEmail = email.isNotEmpty ? email : null;

    return AnimatedBuilder(
      animation: SubscriptionsController.instance,
      builder: (BuildContext context, Widget? child) {
        final effectivePlanId =
            SubscriptionsController.instance.effectivePlanId;
        final tier = artistTierForPlanId(effectivePlanId);
        final planSpec = ArtistSubscriptionCatalog.specForTier(tier);

        final content = FutureBuilder<ArtistDashboardHomeData>(
          future: _future,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<ArtistDashboardHomeData> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done &&
                    !snapshot.hasData) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF0A0A0C),
                    body: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFD4AF37),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Scaffold(
                    backgroundColor: const Color(0xFF0A0A0C),
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Could not load studio dashboard.',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return DashboardLayout(
                  data: snapshot.data!,
                  artistName: artistName,
                  artistEmail: artistEmail,
                  planSpec: planSpec,
                  onRefresh: _refresh,
                  lastUpdated: _lastUpdated,
                  isRefreshing: _isRefreshing,
                );
              },
        );

        if (DebugFlags.showDeveloperUi) {
          return TierMapperDebug(child: content);
        }

        return content;
      },
    );
  }
}

// ===================== SECTION HEADER =====================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(icon, color: const Color(0xFFD4AF37), size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Welcome';
}

String _formatCount(int value) {
  final v = value < 0 ? 0 : value;
  if (v < 1000) return v.toString();

  String fmt(double n, String suffix) {
    final fixed = n >= 10 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
    return '${fixed.replaceAll('.0', '')}$suffix';
  }

  if (v < 1000000) return fmt(v / 1000, 'K');
  if (v < 1000000000) return fmt(v / 1000000, 'M');
  return fmt(v / 1000000000, 'B');
}

String _formatMoney(double value) {
  final v = value.isNaN ? 0 : value;
  final decimals = v >= 100 ? 0 : 2;
  // Default to MWK, can be changed to RAND or USD as needed
  return 'MWK ${v.toStringAsFixed(decimals)}';
}

String _handleFromName(String name) {
  final cleaned = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  final sanitized = cleaned.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  return sanitized.isEmpty ? 'artist' : sanitized;
}

String _initialsFromName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'A';
  final first = parts.first[0].toUpperCase();
  final second = parts.length > 1 ? parts[1][0].toUpperCase() : '';
  return '$first$second';
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Recently';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

// ===================== DASHBOARD LAYOUT =====================
class DashboardLayout extends StatefulWidget {
  const DashboardLayout({
    super.key,
    required this.data,
    required this.artistName,
    required this.planSpec,
    this.artistEmail,
    this.onRefresh,
    this.lastUpdated,
    this.isRefreshing = false,
  });

  final ArtistDashboardHomeData data;
  final String artistName;
  final ArtistSubscriptionPlanSpec planSpec;
  final String? artistEmail;
  final Future<void> Function()? onRefresh;
  final DateTime? lastUpdated;
  final bool isRefreshing;

  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  int _selectedIndex = 0;
  int _primaryIndex = 0;

  static const List<MenuItem> _studioMenuItems = <MenuItem>[
    MenuItem(index: 0, title: 'HOME', icon: Icons.home_outlined),
    MenuItem(index: 1, title: 'UPLOAD', icon: Icons.cloud_upload_outlined),
    MenuItem(index: 2, title: 'GO LIVE', icon: Icons.wifi_tethering_outlined),
    MenuItem(index: 3, title: 'EARNINGS', icon: Icons.payments_outlined),
    MenuItem(index: 4, title: 'PROFILE', icon: Icons.person_outline),
  ];

  void _updateIndex(int index) {
    setState(() {
      _selectedIndex = index;
      if (index <= 4) {
        _primaryIndex = index;
      }
    });
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Best-effort sign out.
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      CommandCenterScreen(
        artistName: widget.artistName,
        data: widget.data,
        onGoLive: () => _updateIndex(2),
        onUpload: () => _updateIndex(1),
      ),
      const ArtistUploadHubScreen(),
      const ArtistGoLiveHubScreen(),
      const ArtistEarningsScreen(showAppBar: false),
      const ArtistProfileScreen(showAppBar: false),
    ];

    final safeIndex = (_selectedIndex < 0 || _selectedIndex >= screens.length)
        ? 0
        : _selectedIndex;
    Widget content = screens[safeIndex];
    if (widget.onRefresh != null) {
      content = RefreshIndicator(
        color: const Color(0xFFD4AF37),
        onRefresh: widget.onRefresh!,
        child: content,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final showSideMenu = constraints.maxWidth >= 800;

        if (showSideMenu) {
          final double menuWidth = constraints.maxWidth < 1000 ? 220.0 : 260.0;
          return Scaffold(
            body: Row(
              children: <Widget>[
                _buildMenu(context, menuWidth: menuWidth),
                Container(
                  width: 1,
                  height: double.infinity,
                  color: const Color(0xFF2C2C30),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('WEAFRICA STUDIO'),
            actions: [
              IconButton(
                tooltip: 'Logout',
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(child: _buildMenu(context, closeOnSelect: true)),
          ),
          body: content,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _primaryIndex,
            onTap: _updateIndex,
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF141416),
            selectedItemColor: const Color(0xFFD4AF37),
            unselectedItemColor: const Color(0xFF9B9B9B),
            items: [
              _navItem(label: 'Home', icon: Icons.home),
              _navItem(label: 'Upload', icon: Icons.cloud_upload_outlined),
              _navItem(label: 'Go Live', icon: Icons.wifi_tethering_outlined),
              _navItem(label: 'Earnings', icon: Icons.payments),
              _navItem(label: 'Profile', icon: Icons.person_outline),
            ],
          ),
        );
      },
    );
  }

  BottomNavigationBarItem _navItem({
    required String label,
    required IconData icon,
    String? badge,
  }) {
    return BottomNavigationBarItem(icon: _navIcon(icon, badge), label: label);
  }

  Widget _navIcon(IconData icon, String? badge) {
    if (badge == null || badge.isEmpty) {
      return Icon(icon);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF141416), width: 1),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            alignment: Alignment.center,
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(
    BuildContext context, {
    double? menuWidth,
    bool closeOnSelect = false,
  }) {
    void handleSelect(int index) {
      _updateIndex(index);
      if (closeOnSelect) {
        Navigator.of(context).pop();
      }
    }

    return LeftMenu(
      width: menuWidth ?? 260,
      selectedIndex: _selectedIndex,
      onItemSelected: handleSelect,
      items: _studioMenuItems,
      userName: widget.artistName,
      userStatusLabel: 'Online',
      onLogout: () => _signOut(context),
    );
  }
}

class _CapabilityGateScreen extends StatefulWidget {
  const _CapabilityGateScreen({
    required this.role,
    required this.capability,
    required this.onDenied,
    required this.builder,
  });

  final UserRole role;
  final CreatorCapability capability;
  final VoidCallback onDenied;
  final Widget Function(BuildContext context) builder;

  @override
  State<_CapabilityGateScreen> createState() => _CapabilityGateScreenState();
}

class _CapabilityGateScreenState extends State<_CapabilityGateScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
        context,
        role: widget.role,
        capability: widget.capability,
      );
      if (!mounted) return;

      if (!allowed) {
        widget.onDenied();
        return;
      }

      setState(() {
        _ready = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return widget.builder(context);
  }
}

// (Removed local MenuItem widget; Studio now uses the shared core/navigation LeftMenu.)

// ===================== COMMAND CENTER SCREEN =====================
class CommandCenterScreen extends StatelessWidget {
  const CommandCenterScreen({
    super.key,
    required this.artistName,
    required this.data,
    required this.onGoLive,
    required this.onUpload,
  });

  final String artistName;
  final ArtistDashboardHomeData data;
  final VoidCallback onGoLive;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final goLiveColor = Theme.of(context).colorScheme.error;
    return Container(
      color: const Color(0xFF0A0A0C),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        children: [
          const _SectionHeader(title: 'HOME', icon: Icons.home),
          const SizedBox(height: 14),
          Text(
            '${_greeting()}, $artistName',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Upload. Go Live. Earn.',
            style: TextStyle(color: Color(0xFF9B9B9B), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: goLiveColor,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              onPressed: onGoLive,
              child: const Text('GO LIVE'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text(
                'UPLOAD',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossAxisCount = w < 520 ? 1 : (w < 950 ? 2 : 3);
              final aspect = crossAxisCount == 1 ? 2.2 : 1.55;

              return GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: aspect,
                ),
                children: <Widget>[
                  _StudioMetricCard(
                    label: 'PLAYS',
                    value: _formatCount(data.totalPlays),
                    icon: Icons.play_circle,
                    tooltip: 'Total plays/streams (best-effort)',
                  ),
                  _StudioMetricCard(
                    label: 'EARNINGS',
                    value: _formatMoney(data.totalEarnings),
                    icon: Icons.monetization_on,
                    tooltip: 'Total earnings (best-effort)',
                  ),
                  _StudioMetricCard(
                    label: 'FOLLOWERS',
                    value: _formatCount(data.followersCount),
                    icon: Icons.people,
                    tooltip: 'Total followers/fans',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdvancedAnalyticsScreen extends StatelessWidget {
  const AdvancedAnalyticsScreen({
    super.key,
    required this.artistName,
    required this.planSpec,
  });

  final String artistName;
  final ArtistSubscriptionPlanSpec planSpec;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0C),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SectionHeader(
                    title: 'ADVANCED ANALYTICS',
                    icon: Icons.analytics,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Analytics',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${planSpec.analyticsLabel} analytics • Earnings split: ${planSpec.earningsSplitPercent}% • Withdrawals: ${planSpec.withdrawalFrequencyLabel}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF9B9B9B)),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _StudioCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.workspace_premium, color: Color(0xFFD4AF37)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${planSpec.tierDisplayName} • Earnings: ${planSpec.monetizationLabel} (${planSpec.earningsSplitPercent}%) • Withdrawals: ${planSpec.withdrawalLabel} (${planSpec.withdrawalFrequencyLabel})',
                        style: const TextStyle(
                          color: Color(0xFF9B9B9B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _FinancialCard(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _GrowthAnalytics(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _AchievementsGrid(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ===================== MUSIC EMPIRE SCREEN =====================
enum _MusicEmpireTab { tracks, videos, albums }

class MusicEmpireScreen extends StatefulWidget {
  const MusicEmpireScreen({
    super.key,
    required this.data,
    required this.planSpec,
  });

  final ArtistDashboardHomeData data;
  final ArtistSubscriptionPlanSpec planSpec;

  @override
  State<MusicEmpireScreen> createState() => _MusicEmpireScreenState();
}

class _MusicEmpireScreenState extends State<MusicEmpireScreen> {
  _MusicEmpireTab _selected = _MusicEmpireTab.tracks;

  void _openContent(BuildContext context, ArtistContentTab tab) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistContentScreen(initialTab: tab),
      ),
    );
  }

  List<Track> _queueFromAll(List<Track> tracks, int index) {
    final queue = <Track>[];
    for (var i = index + 1; i < tracks.length; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      queue.add(t);
    }
    for (var i = 0; i < index; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      queue.add(t);
    }
    return queue;
  }

  void _playAndOpen(
    BuildContext context,
    Track track,
    List<Track> tracks,
    int index,
  ) {
    if (track.audioUri == null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This track has no audio URL yet.')),
        );
      return;
    }

    final queue = _queueFromAll(tracks, index);
    PlaybackController.instance.play(track, queue: queue);
    openPlayer(context);
  }

  List<Widget> _buildTrackCards(BuildContext context) {
    final tracks = widget.data.recentSongs;
    if (tracks.isEmpty) {
      return <Widget>[
        _TrackCard(
          title: 'No tracks yet',
          subtitle: 'Tap to upload your first song',
          imageUrl: '',
          isPlayable: false,
          onTap: () => _openContent(context, ArtistContentTab.upload),
        ),
      ];
    }

    final cards = <Widget>[];
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final title = track.title.trim().isEmpty
          ? 'Untitled Track'
          : track.title.trim();
      final artist = track.artist.trim().isEmpty
          ? 'Unknown Artist'
          : track.artist.trim();

      cards.add(
        _TrackCard(
          title: title,
          subtitle: artist,
          imageUrl: track.artworkUri?.toString() ?? '',
          isPlayable: track.audioUri != null,
          onTap: () => _playAndOpen(context, track, tracks, i),
        ),
      );
    }

    return cards;
  }

  List<Widget> _buildVideoCards(BuildContext context) {
    final videos = widget.data.recentVideos;
    if (videos.isEmpty) {
      return <Widget>[
        _VideoCard(
          title: 'No videos yet',
          subtitle: 'Tap to upload a video',
          imageUrl: '',
          onTap: () => _openContent(context, ArtistContentTab.upload),
        ),
      ];
    }

    return <Widget>[
      for (final v in videos)
        _VideoCard(
          title: v.title.trim().isEmpty ? 'Untitled Video' : v.title.trim(),
          subtitle: _formatDate(v.createdAt),
          imageUrl: (v.thumbnailUrl ?? '').trim(),
          onTap: () => _openContent(context, ArtistContentTab.videos),
        ),
    ];
  }

  List<Widget> _buildAlbumCards(BuildContext context) {
    return <Widget>[
      _AlbumCard(
        title: 'Albums',
        subtitle: 'View and manage albums',
        onTap: () => _openContent(context, ArtistContentTab.albums),
      ),
      _AlbumCard(
        title: 'Create album',
        subtitle: 'Tap to start a new album',
        onTap: () => _openContent(context, ArtistContentTab.upload),
      ),
    ];
  }

  List<Widget> _buildRecentUploads(BuildContext context) {
    final widgets = <Widget>[];

    final songs = widget.data.recentSongs;
    for (int i = 0; i < songs.length && widgets.length < 2; i++) {
      final song = songs[i];
      widgets.add(
        _UploadItem(
          title: song.title.trim().isEmpty ? 'Untitled Track' : song.title,
          date: _formatDate(song.createdAt),
          status: 'Published',
          onTap: () => _playAndOpen(context, song, songs, i),
        ),
      );
    }

    final videos = widget.data.recentVideos;
    for (int i = 0; i < videos.length && widgets.length < 2; i++) {
      final video = videos[i];
      widgets.add(
        _UploadItem(
          title: video.title.trim().isEmpty ? 'Untitled Video' : video.title,
          date: _formatDate(video.createdAt),
          status: 'Processing',
          onTap: () => _openContent(context, ArtistContentTab.videos),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.addAll(<Widget>[
        _UploadItem(
          title: 'First Upload',
          date: 'Recently',
          status: 'Draft',
          onTap: () => _openContent(context, ArtistContentTab.upload),
        ),
        const SizedBox(height: 12),
        _UploadItem(
          title: 'Studio Session',
          date: 'Recently',
          status: 'Draft',
          onTap: () => _openContent(context, ArtistContentTab.upload),
        ),
      ]);
      return widgets;
    }

    // Add spacing between the first two items.
    if (widgets.length > 1) {
      widgets.insert(1, const SizedBox(height: 12));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return Container(
      color: const Color(0xFF0A0A0C),
      child: CustomScrollView(
        slivers: <Widget>[
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SectionHeader(
                    title: 'MUSIC CATALOG',
                    icon: Icons.library_music,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your catalog',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage your tracks, videos, and albums',
                    style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B)),
                  ),
                ],
              ),
            ),
          ),

          // Tab Selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _TabSelector(
                selected: _selected,
                onChanged: (t) => setState(() => _selected = t),
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(top: 24)),

          // Stats Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.crossAxisExtent;
                final crossAxisCount = w < 520
                    ? 1
                    : w < 950
                    ? 2
                    : w < 1200
                    ? 3
                    : 4;
                final aspect = crossAxisCount == 1
                    ? 2.2
                    : (crossAxisCount == 2 ? 1.25 : 1.55);

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: aspect,
                  ),
                  delegate: SliverChildListDelegate.fixed(<Widget>[
                    _StudioMetricCard(
                      label: 'RECENT TRACKS',
                      value: _formatCount(data.recentSongs.length),
                      icon: Icons.library_music,
                      tooltip: 'Tracks loaded in this view (not total catalog)',
                    ),
                    _StudioMetricCard(
                      label: 'RECENT VIDEOS',
                      value: _formatCount(data.recentVideos.length),
                      icon: Icons.video_library,
                      tooltip: 'Videos loaded in this view (not total catalog)',
                    ),
                    _StudioMetricCard(
                      label: 'STREAMS',
                      value: _formatCount(data.totalPlays),
                      icon: Icons.play_circle,
                      tooltip: 'Total plays/streams (best-effort)',
                    ),
                    _StudioMetricCard(
                      label: 'EARNINGS',
                      value: _formatMoney(data.totalEarnings),
                      icon: Icons.monetization_on,
                      tooltip: 'Total earnings (best-effort)',
                    ),
                    _StudioMetricCard(
                      label: 'COINS',
                      value: _formatCount(data.coinBalance.round()),
                      icon: Icons.monetization_on_outlined,
                      tooltip: 'Your current coin balance',
                    ),
                  ]),
                );
              },
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(top: 24)),

          // Content Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.crossAxisExtent;
                final crossAxisCount = w < 520
                    ? 2
                    : w < 900
                    ? 3
                    : w < 1200
                    ? 4
                    : 5;
                final aspect = crossAxisCount <= 2 ? 1.0 : 1.05;

                final children = switch (_selected) {
                  _MusicEmpireTab.tracks => _buildTrackCards(context),
                  _MusicEmpireTab.videos => _buildVideoCards(context),
                  _MusicEmpireTab.albums => _buildAlbumCards(context),
                };

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: aspect,
                  ),
                  delegate: SliverChildListDelegate.fixed(children),
                );
              },
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(top: 24)),

          // Recent Uploads
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'RECENT UPLOADS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9B9B9B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildRecentUploads(context),
                ],
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
        ],
      ),
    );
  }
}

// ===================== FAN CLUB SCREEN =====================
class FanClubScreen extends StatelessWidget {
  const FanClubScreen({
    super.key,
    required this.artistName,
    required this.planSpec,
    required this.onManageSubscription,
  });

  final String artistName;
  final ArtistSubscriptionPlanSpec planSpec;
  final VoidCallback onManageSubscription;

  @override
  Widget build(BuildContext context) {
    final canUse = planSpec.canUseFanClub;

    return Container(
      color: const Color(0xFF0A0A0C),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SectionHeader(
                    title: 'FAN CLUB',
                    icon: Icons.favorite_border,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Build a stronger community, $artistName',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Offer exclusive tiers and perks to supporters',
                    style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B)),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(top: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _StudioCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FAN CLUB TIERS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9B9B9B),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!canUse) ...[
                      const Text(
                        'Supporter tiers start on Artist Premium.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upgrade to unlock fan support, exclusive supporter perks, and higher-value monetization tools.',
                        style: TextStyle(
                          color: Color(0xFF9B9B9B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: onManageSubscription,
                        child: const Text('Upgrade'),
                      ),
                    ] else ...[
                      Text(
                        planSpec.supporterPerksLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tier management tools will appear here for your Premium supporters.',
                        style: TextStyle(
                          color: Color(0xFF9B9B9B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
        ],
      ),
    );
  }
}

// ===================== TAB SELECTOR =====================
class _TabSelector extends StatelessWidget {
  const _TabSelector({required this.selected, required this.onChanged});

  final _MusicEmpireTab selected;
  final ValueChanged<_MusicEmpireTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Row(
        children: <Widget>[
          _TabItem(
            label: 'TRACKS',
            isSelected: selected == _MusicEmpireTab.tracks,
            onTap: () => onChanged(_MusicEmpireTab.tracks),
          ),
          _TabItem(
            label: 'VIDEOS',
            isSelected: selected == _MusicEmpireTab.videos,
            onTap: () => onChanged(_MusicEmpireTab.videos),
          ),
          _TabItem(
            label: 'ALBUMS',
            isSelected: selected == _MusicEmpireTab.albums,
            onTap: () => onChanged(_MusicEmpireTab.albums),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : Colors.transparent,
                borderRadius: radius,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.black : const Color(0xFF9B9B9B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== TRACK CARD =====================
class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isPlayable,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final bool isPlayable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.trim().isEmpty ? 'Untitled Track' : title.trim();
    final safeSubtitle = subtitle.trim().isEmpty
        ? 'Unknown Artist'
        : subtitle.trim();
    final accent = Theme.of(context).colorScheme.primary;

    return _StudioCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      gradient: const LinearGradient(
        colors: <Color>[_kStudioSurface, _kStudioSurfaceAlt],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _StudioNetworkImage(
                  imageUrl: imageUrl,
                  seed: safeTitle,
                  icon: Icons.music_note,
                  borderRadius: BorderRadius.zero,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.70),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    isPlayable ? Icons.play_circle_fill : Icons.lock,
                    color: isPlayable
                        ? accent
                        : Colors.white.withValues(alpha: 140),
                    size: 46,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  safeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isPlayable ? Colors.white : const Color(0xFF9B9B9B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  safeSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9B9B9B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.trim().isEmpty ? 'Untitled Video' : title.trim();
    final safeSubtitle = subtitle.trim().isEmpty ? 'Recently' : subtitle.trim();
    final accent = Theme.of(context).colorScheme.primary;

    return _StudioCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      gradient: const LinearGradient(
        colors: <Color>[_kStudioSurface, _kStudioSurfaceAlt],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _StudioNetworkImage(
                  imageUrl: imageUrl,
                  seed: safeTitle,
                  icon: Icons.video_library,
                  borderRadius: BorderRadius.zero,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: accent.withValues(alpha: 200),
                    size: 46,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  safeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  safeSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9B9B9B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.title, required this.subtitle, this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.trim().isEmpty ? 'Albums' : title.trim();
    final safeSubtitle = subtitle.trim().isEmpty
        ? 'Manage albums'
        : subtitle.trim();
    final accent = Theme.of(context).colorScheme.primary;

    return _StudioCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      onTap: onTap,
      gradient: LinearGradient(
        colors: <Color>[_kStudioSurface, accent.withValues(alpha: 0.06)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Icon(Icons.album_outlined, size: 18, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            safeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            safeSubtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9B9B9B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              Icons.chevron_right,
              color: accent.withValues(alpha: 180),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== UPLOAD ITEM =====================
class _UploadItem extends StatelessWidget {
  final String title;
  final String date;
  final String status;
  final VoidCallback? onTap;

  const _UploadItem({
    required this.title,
    required this.date,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final ink = Ink(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: radius,
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.cloud_upload,
              color: Color(0xFFD4AF37),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'Published'
                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: status == 'Published'
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return ink;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        mouseCursor: SystemMouseCursors.click,
        child: ink,
      ),
    );
  }
}

class WarRoomScreen extends StatefulWidget {
  const WarRoomScreen({
    super.key,
    required this.refreshSeed,
    required this.recentTracks,
  });

  final int refreshSeed;
  final List<Track> recentTracks;

  @override
  State<WarRoomScreen> createState() => _WarRoomScreenState();
}

class _WarRoomScreenState extends State<WarRoomScreen> {
  final ArtistIdentityService _identity = ArtistIdentityService();
  final BattleRepository _battles = BattleRepository();
  final ArtistRepository _artists = ArtistRepository();

  late Future<_WarRoomData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant WarRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed) {
      setState(() {
        _future = _load();
      });
    }
  }

  int _readInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<_WarRoomData> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    final artistId = await _identity.resolveArtistId();
    final resolvedArtistId = (artistId ?? '').trim();

    var totalBattles = 0;
    if (resolvedArtistId.isNotEmpty) {
      final stats = await _artists.getArtistStats(resolvedArtistId);
      totalBattles = _readInt(stats['total_battles']);
    }

    final activeRows = await _battles.getActiveBattles(
      resolvedArtistId,
      firebaseUid: uid,
      limit: 20,
    );

    final activeBattles = activeRows
        .map(_BattleSummary.fromSupabase)
        .where((b) => b.id.trim().isNotEmpty)
        .toList(growable: false);

    return _WarRoomData(
      totalBattles: totalBattles,
      activeBattles: activeBattles,
    );
  }

  void _openCreateBattle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Please sign in again.')));
      return;
    }

    final rawName = (user.displayName ?? '').trim();
    final hostName = rawName.isNotEmpty ? rawName : UserRole.artist.label;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoLiveSetupScreen(
          role: UserRole.artist,
          hostId: user.uid,
          hostName: hostName,
          initialBattleModeEnabled: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WarRoomData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _WarRoomData.empty();
        final isLoading = snapshot.connectionState != ConnectionState.done;

        return CustomScrollView(
          slivers: <Widget>[
            // ================= HEADER =================
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _SectionHeader(
                            title: 'WAR ROOM',
                            icon: Icons.sports_mma,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'War Room',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Battles, invites, and live status',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Color(0xFF9B9B9B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      key: const Key('create_battle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _openCreateBattle,
                      child: const Text(
                        'Create Battle',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (snapshot.hasError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _StudioCard(
                    padding: const EdgeInsets.all(16),
                    borderColor: const Color(0xFFEF4444),
                    gradient: LinearGradient(
                      colors: <Color>[
                        _kStudioSurface,
                        const Color(0xFFEF4444).withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.wifi_off, color: Color(0xFFEF4444)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Could not load battle data. Showing available offline data.',
                            style: TextStyle(
                              color: Color(0xFF9B9B9B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ================= STATS GRID =================
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.crossAxisExtent;
                  final crossAxisCount = w < 520
                      ? 1
                      : w < 950
                      ? 2
                      : w < 1200
                      ? 3
                      : 4;

                  final aspect = crossAxisCount == 1
                      ? 2.2
                      : (crossAxisCount == 2 ? 1.25 : 1.55);

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: aspect,
                    ),
                    delegate: SliverChildListDelegate.fixed(<Widget>[
                      _StudioMetricCard(
                        label: 'TOTAL BATTLES',
                        value: _formatCount(data.totalBattles),
                        icon: Icons.sports_mma,
                        tooltip:
                            'All battles found for your artist (best-effort)',
                      ),
                      _StudioMetricCard(
                        label: 'LIVE BATTLES',
                        value: _formatCount(data.activeBattles.length),
                        icon: Icons.wifi_tethering,
                        tooltip: isLoading
                            ? 'Loading…'
                            : 'Active (non-completed) battles',
                      ),
                    ]),
                  );
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ================= ACTIVE BATTLES =================
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'ACTIVE BATTLES',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9B9B9B),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed(
                  _buildActiveBattleCards(data),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ================= HISTORY =================
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'BATTLE HISTORY',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9B9B9B),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _StudioCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.history, color: Color(0xFFD4AF37)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No battle history loaded yet.',
                          style: TextStyle(
                            color: Color(0xFF9B9B9B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const _StudioValueText(
                        value: '0',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      },
    );
  }

  List<Widget> _buildActiveBattleCards(_WarRoomData data) {
    final cards = <Widget>[];
    final active = data.activeBattles;

    if (active.isEmpty) {
      cards.add(
        const _WarBattleCard(
          title: 'No active battles',
          status: '—',
          createdAt: null,
          opponentSeed: 'weafrica',
        ),
      );
      return cards;
    }

    for (final battle in active.take(2)) {
      cards.add(
        _WarBattleCard(
          title: battle.title,
          status: battle.status,
          createdAt: battle.createdAt,
          opponentSeed: battle.opponentSeed,
        ),
      );
      cards.add(const SizedBox(height: 16));
    }

    if (cards.isNotEmpty) {
      cards.removeLast();
    }
    return cards;
  }
}

class _WarRoomData {
  const _WarRoomData({required this.totalBattles, required this.activeBattles});

  const _WarRoomData.empty()
    : totalBattles = 0,
      activeBattles = const <_BattleSummary>[];

  final int totalBattles;
  final List<_BattleSummary> activeBattles;
}

class _BattleSummary {
  const _BattleSummary({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String status;
  final DateTime? createdAt;

  String get title {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return 'Battle';
    final short = trimmed.length > 8 ? trimmed.substring(0, 8) : trimmed;
    return 'Battle $short';
  }

  String get opponentSeed => id.trim().isEmpty ? 'weafrica' : id.trim();

  factory _BattleSummary.fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final statusRaw = (row['status'] ?? '').toString().trim();
    final status = statusRaw.isEmpty ? 'ACTIVE' : statusRaw.toUpperCase();

    DateTime? createdAt;
    final createdAtRaw = row['created_at'] ?? row['createdAt'];
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw.toString());
    }

    return _BattleSummary(id: id, status: status, createdAt: createdAt);
  }
}

class _WarBattleCard extends StatelessWidget {
  const _WarBattleCard({
    required this.title,
    required this.status,
    required this.createdAt,
    required this.opponentSeed,
  });

  final String title;
  final String status;
  final DateTime? createdAt;
  final String opponentSeed;

  @override
  Widget build(BuildContext context) {
    return _StudioCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            height: 56,
            child: _StudioNetworkImage(
              imageUrl: '',
              seed: opponentSeed,
              icon: Icons.person,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(
                            0xFFD4AF37,
                          ).withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        status.trim().isEmpty ? '—' : status,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      createdAt == null ? '—' : _formatDate(createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9B9B9B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Color(0xFF9B9B9B),
          ),
        ],
      ),
    );
  }
}

class NationScreen extends StatelessWidget {
  const NationScreen({super.key, required this.data});

  final ArtistDashboardHomeData data;

  List<ArtistNotificationItem> _activityItems() {
    return data.recentNotifications.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final followers = data.followersCount;
    final engagementPct = followers <= 0
        ? 0.0
        : (followers / 10000).clamp(0.0, 1.0);
    final engagementLabel = followers <= 0
        ? '0 fans engaged'
        : '${_formatCount(followers)} fans engaged';

    final activity = _activityItems();

    return CustomScrollView(
      slivers: <Widget>[
        // ================= HEADER =================
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionHeader(title: 'THE NATION', icon: Icons.people),
                SizedBox(height: 16),
                Text(
                  'Nation',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Fans, messages, and activity',
                  style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B)),
                ),
              ],
            ),
          ),
        ),

        // ================= FAN METER =================
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _StudioCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'LIVE FAN METER',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFFD4AF37),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatCount(followers),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: engagementPct,
                    minHeight: 10,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFD4AF37),
                    ),
                    backgroundColor: const Color(0xFF2C2C30),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    engagementLabel,
                    style: const TextStyle(
                      color: Color(0xFF9B9B9B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ================= NATION METRICS =================
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.crossAxisExtent;
              final crossAxisCount = w < 520
                  ? 1
                  : w < 950
                  ? 2
                  : w < 1200
                  ? 3
                  : 4;

              final aspect = crossAxisCount == 1
                  ? 2.2
                  : (crossAxisCount == 2 ? 1.25 : 1.55);

              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: aspect,
                ),
                delegate: SliverChildListDelegate.fixed(<Widget>[
                  _StudioMetricCard(
                    label: 'FANS',
                    value: _formatCount(data.followersCount),
                    icon: Icons.people,
                    tooltip: 'Total followers/fans',
                  ),
                  _StudioMetricCard(
                    label: 'UNREAD',
                    value: _formatCount(data.unreadMessagesCount),
                    icon: Icons.chat_bubble,
                    tooltip: 'Unread messages',
                  ),
                  _StudioMetricCard(
                    label: 'NOTIFICATIONS',
                    value: _formatCount(data.notificationsCount),
                    icon: Icons.notifications,
                    tooltip: 'Notifications count (best-effort)',
                  ),
                  _StudioMetricCard(
                    label: 'STREAMS',
                    value: _formatCount(data.totalPlays),
                    icon: Icons.play_circle,
                    tooltip: 'Total plays/streams (best-effort)',
                  ),
                ]),
              );
            },
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ================= RECENT ACTIVITY =================
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _StudioCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Text(
                        'RECENT ACTIVITY',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF9B9B9B),
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      _StudioValueText(
                        value: _formatCount(data.notificationsCount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (activity.isEmpty)
                    const Text(
                      'No recent activity yet.',
                      style: TextStyle(
                        color: Color(0xFF9B9B9B),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    ...activity.asMap().entries.expand((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return <Widget>[
                        _ActivityRow(title: item.title, body: item.body),
                        if (index != activity.length - 1)
                          const SizedBox(height: 12),
                      ];
                    }),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.trim().isEmpty ? 'Activity' : title.trim();
    final safeBody = body.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
            ),
          ),
          child: const Icon(
            Icons.notifications,
            color: Color(0xFFD4AF37),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                safeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (safeBody.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  safeBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9B9B9B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== THRONE ROOM SCREEN =====================
class ThroneRoomScreen extends StatelessWidget {
  const ThroneRoomScreen({super.key, required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0C),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  Text(
                    'THRONE ROOM',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Your empire',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Manage your profile, earnings, and account',
                    style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B)),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ProfileCard(artistName: artistName),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _FinancialCard(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _GrowthAnalytics(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _AchievementsGrid(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _PowerUpCard(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _AccountControls(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ===================== PROFILE CARD =====================
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFD4AF37), Color(0xFFF5D742)],
                  ),
                ),
                child: Center(
                  child: Text(
                    _initialsFromName(artistName),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      artistName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${_handleFromName(artistName)} - Ghana',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9B9B9B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===================== FINANCIAL CARD =====================
class _FinancialCard extends StatelessWidget {
  const _FinancialCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'FINANCIAL EMPIRE',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 20),
          _RevenueBar(
            label: 'STREAMS',
            percentage: 0,
            color: Color(0xFFD4AF37),
          ),
          SizedBox(height: 10),
          _RevenueBar(
            label: 'BATTLES',
            percentage: 0,
            color: Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }
}

class _RevenueBar extends StatelessWidget {
  final String label;
  final int percentage;
  final Color color;

  const _RevenueBar({
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF242428),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * (percentage / 100),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ===================== GROWTH ANALYTICS =====================
class _GrowthAnalytics extends StatelessWidget {
  const _GrowthAnalytics();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: const _GrowthMetric(
        label: 'FAN GROWTH',
        percentage: 0,
        color: Color(0xFF10B981),
      ),
    );
  }
}

class _GrowthMetric extends StatelessWidget {
  final String label;
  final int percentage;
  final Color color;

  const _GrowthMetric({
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF242428),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * (percentage / 100),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ===================== ACHIEVEMENTS GRID =====================
class _AchievementsGrid extends StatelessWidget {
  const _AchievementsGrid();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          int count = constraints.maxWidth < 600
              ? 3
              : constraints.maxWidth < 1000
              ? 4
              : 6;

          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: const <Widget>[
              Icon(Icons.emoji_events, color: Color(0xFFD4AF37)),
              Icon(Icons.local_fire_department, color: Color(0xFFF59E0B)),
              Icon(Icons.star, color: Color(0xFF10B981)),
              Icon(Icons.military_tech, color: Color(0xFF3B82F6)),
              Icon(Icons.diamond, color: Color(0xFF8B5CF6)),
              Icon(Icons.gps_fixed, color: Color(0xFFEF4444)),
            ],
          );
        },
      ),
    );
  }
}

// ===================== POWER UP CARD =====================
class _PowerUpCard extends StatelessWidget {
  const _PowerUpCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Text(
          'UPGRADE YOUR ARTIST PLAN',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
    );
  }
}

// ===================== ACCOUNT CONTROLS =====================
class _AccountControls extends StatelessWidget {
  const _AccountControls();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: Colors.white),
            title: const Text(
              'Profile settings',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF9B9B9B)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ArtistProfileSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(color: Color(0xFF2C2C30)),
          const ListTile(
            leading: Icon(Icons.notifications, color: Colors.white),
            title: Text('Notifications', style: TextStyle(color: Colors.white)),
          ),
          const Divider(color: Color(0xFF2C2C30)),
          const ListTile(
            leading: Icon(Icons.lock, color: Colors.white),
            title: Text(
              'Privacy & Security',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
