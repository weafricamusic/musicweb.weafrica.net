import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:glass_kit/glass_kit.dart';

import '../../app/config/api_env.dart';
import '../../app/config/debug_flags.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../app/widgets/stage_background.dart';
import '../ai_creator/ai_creator_screen.dart';
import '../artist_dashboard/screens/artist_profile_settings_screen.dart';
import '../auth/user_role.dart';
import '../auth/user_role_intent_store.dart';
import '../auth/user_role_resolver.dart';
import '../dj_dashboard/screens/dj_profile_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../auth/auth_actions.dart';
import '../../services/notification_service.dart';
import '../beat_assistant/beat_audio_screen.dart';
import '../subscriptions/role_based_subscription_screen.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../subscriptions/models/subscription_plan.dart';
import 'about_weafrica_music_page.dart';
import 'download_stats.dart';
import 'downloads_settings_page.dart';
import 'rate_app.dart';
import 'settings_controller.dart';
import 'settings_models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFF2D572);
  
  final _controller = SettingsController.instance;
  UserRole? _role;
  bool _showSearch = false;
  String _query = '';
  
  late AnimationController _headerController;
  late Animation<double> _headerAnimation;

  String _badgeTextForPlanId(String planId) {
    final normalized = canonicalPlanId(planId);
    if (normalized.isEmpty) return 'PLAN';
    switch (normalized) {
      case 'platinum':
        return 'VIP';
      case 'premium':
        return 'PREMIUM';
      case 'artist_starter':
        return 'ARTIST FREE';
      case 'artist_pro':
        return 'ARTIST PRO';
      case 'artist_premium':
        return 'ARTIST PREMIUM';
      case 'dj_starter':
        return 'DJ FREE';
      case 'dj_pro':
        return 'DJ PRO';
      case 'dj_premium':
        return 'DJ PREMIUM';
      case 'free':
        return 'FREE';
      default:
        return normalized.split(RegExp(r'[_\-\s]+')).first.toUpperCase();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.load();
    unawaited(_loadRole());

    // Keep plan badge/entitlements fresh when opening Settings.
    SubscriptionsController.instance.initialize();
    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(SubscriptionsController.instance.refreshMe());
    }
    
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    
    _headerAnimation = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final resolved = await UserRoleResolver.resolveCurrentUser();
      final intent = await UserRoleIntentStore.getRole();

      final r = (intent == UserRole.consumer) ? UserRole.consumer : resolved;
      if (!mounted) return;
      setState(() => _role = r);
    } catch (_) {
      if (!mounted) return;
      setState(() => _role = UserRole.consumer);
    }
  }

  Future<void> _setAudioQualityWithEntitlements(BuildContext context, AudioQuality v) async {
    final subs = SubscriptionsController.instance;
    final bool canUseHigh = subs.canUseHighQualityAudio;

    if (v == AudioQuality.high && !canUseHigh) {
      final upgrade = await _showPremiumUpgradeDialog(context);
      if (upgrade == true) {
        if (!mounted) return;
        await Navigator.of(this.context).push(
          MaterialPageRoute(builder: (_) => RoleBasedSubscriptionScreen(roleOverride: _role)),
        );
      }
      return;
    }

    await _controller.setAudioQuality(v);
  }

  Future<bool?> _showPremiumUpgradeDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          width: 320,
          height: 300,
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
                  color: _gold.withAlpha(26),
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold.withAlpha(77)),
                ),
                child: const Icon(
                  Icons.star,
                  color: _gold,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'PREMIUM FEATURE',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'High-quality audio is available on Premium Listener (and higher).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('NOT NOW'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_gold, _goldLight],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('UPGRADE'),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: _showSearch
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search settings…',
                      hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                      isDense: true,
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search, color: _gold),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  )
                : ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_gold, _goldLight],
                    ).createShader(bounds),
                    child: const Text(
                      'SETTINGS',
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
                  tooltip: _showSearch ? 'Close search' : 'Search',
                  onPressed: () => setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _query = '';
                  }),
                  icon: Icon(
                    _showSearch ? Icons.close : Icons.search,
                    color: _gold,
                  ),
                ),
              ),
            ],
          ),
          body: StageBackground(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 32),
              children: [
                // Profile Summary Card (if logged in)
                _buildProfileSummary(),
                const SizedBox(height: 20),
                
                // Settings Sections
                ..._buildSections(),
              ]
                  .where((w) => _matchesQuery(w))
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileSummary() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _headerAnimation,
      child: GlassContainer(
        width: double.infinity,
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _gold, width: 2),
              ),
              child: CircleAvatar(
                backgroundColor: _gold.withAlpha(26),
                backgroundImage: user.photoURL != null
                    ? NetworkImage(user.photoURL!)
                    : null,
                child: user.photoURL == null
                    ? Text(
                        (user.displayName ?? user.email ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.displayName ?? 'Music Lover',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(128),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold.withAlpha(26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withAlpha(77)),
              ),
              child: const Text(
                'FREE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections() {
    return [
      _section(
        context,
        title: 'ACCOUNT',
        icon: Icons.person,
        children: [
          _navRow(
            context,
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'Edit your profile information',
            onTap: () {
              final role = _role ?? UserRole.consumer;
              if (role == UserRole.artist) {
                _open(context, const ArtistProfileSettingsScreen());
                return;
              }
              if (role == UserRole.dj) {
                _open(context, const DjProfileScreen());
                return;
              }
              _open(context, const EditProfileScreen());
            },
          ),
          _buildSubscriptionRow(),
          if (_role == UserRole.dj || _role == UserRole.artist) ...[
            _navRow(
              context,
              icon: Icons.music_note,
              title: 'Beat MP3 Generator',
              subtitle: 'Generate a beat MP3 using AI',
              onTap: () => _open(context, BeatAudioScreen(role: _role!)),
            ),
            _navRow(
              context,
              icon: Icons.library_music,
              title: 'Your Beats',
              subtitle: 'Saved beats you can replay offline',
              onTap: () => _open(context, BeatAudioScreen(role: _role!, openLibrary: true)),
            ),
            _navRow(
              context,
              icon: Icons.auto_awesome,
              title: 'AI Creator',
              subtitle: 'Generate AI music and track status',
              onTap: () => _open(context, AiCreatorScreen(role: _role!)),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      
      _section(
        context,
        title: 'PLAYBACK',
        icon: Icons.play_arrow,
        children: [
          _switchRow(
            context,
            icon: Icons.play_arrow_outlined,
            title: 'Auto-play',
            subtitle: 'Automatically play similar songs',
            value: _controller.autoPlay,
            onChanged: _controller.setAutoPlay,
          ),
          _dropdownRow<AudioQuality>(
            context,
            icon: Icons.volume_up,
            title: 'Audio Quality',
            subtitle: 'Current: ${_controller.audioQuality.label}',
            value: _controller.audioQuality,
            values: AudioQuality.values,
            labelFor: (v) => v.label,
            onChanged: (v) => _setAudioQualityWithEntitlements(context, v),
          ),
          _switchRow(
            context,
            icon: Icons.graphic_eq,
            title: 'Normalize Volume',
            subtitle: 'Balance volume across tracks',
            value: _controller.normalizeVolume,
            onChanged: _controller.setNormalizeVolume,
          ),
        ],
      ),
      const SizedBox(height: 16),
      
      _section(
        context,
        title: 'APP SETTINGS',
        icon: Icons.settings_applications,
        children: [
          _dropdownRow<AppThemeMode>(
            context,
            icon: Icons.dark_mode,
            title: 'Theme',
            subtitle: 'App appearance',
            value: _controller.themeMode,
            values: AppThemeMode.values,
            labelFor: (v) => v.label,
            onChanged: (v) => _controller.setThemeMode(v),
          ),
          _dropdownRow<AppLanguage>(
            context,
            icon: Icons.language,
            title: 'Language',
            subtitle: 'App language',
            value: _controller.language,
            values: AppLanguage.values,
            labelFor: (v) => v.label,
            onChanged: (v) => _controller.setLanguage(v),
          ),
          _switchRow(
            context,
            icon: Icons.wifi,
            title: 'Wi‑Fi Only',
            subtitle: 'Stream only on Wi‑Fi',
            value: _controller.wifiOnly,
            onChanged: _controller.setWifiOnly,
          ),
          _switchRow(
            context,
            icon: Icons.warning_amber,
            title: 'Explicit Content',
            subtitle: 'Allow explicit content',
            value: _controller.explicitContent,
            onChanged: _controller.setExplicitContent,
          ),
        ],
      ),
      const SizedBox(height: 16),
      
      _section(
        context,
        title: 'NOTIFICATIONS',
        icon: Icons.notifications,
        children: [
          _switchRow(
            context,
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'Receive app notifications',
            value: _controller.pushNotifications,
            onChanged: _controller.setPushNotifications,
          ),
          _switchRow(
            context,
            icon: Icons.new_releases,
            title: 'New Releases',
            subtitle: 'Get notified about new music',
            value: _controller.newReleases,
            onChanged: _controller.setNewReleases,
          ),
          _switchRow(
            context,
            icon: Icons.favorite_border,
            title: 'Favorites Updates',
            subtitle: 'Updates from favorite artists',
            value: _controller.favoritesUpdates,
            onChanged: _controller.setFavoritesUpdates,
          ),
        ],
      ),
      const SizedBox(height: 16),
      
      _section(
        context,
        title: 'STORAGE',
        icon: Icons.storage,
        children: [
          FutureBuilder<DownloadStats>(
            future: getDownloadStats(),
            builder: (context, snap) {
              final stats = snap.data;
              final subtitle = stats == null
                  ? 'Calculating…'
                  : stats.fileCount == 0
                      ? 'No downloads'
                      : '${stats.fileCount} files • ${stats.prettySize}';
              return _navRow(
                context,
                icon: Icons.download_for_offline,
                title: 'Downloads',
                subtitle: subtitle,
                onTap: () => _open(context, const DownloadsSettingsPage()),
              );
            },
          ),
          _actionRow(
            context,
            icon: Icons.cleaning_services,
            title: 'Clear Cache',
            subtitle: 'Free up storage space',
            action: _GoldPill(text: 'CLEAR'),
            onTap: () async {
              await _clearCache();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Cache cleared.'),
                  backgroundColor: _gold,
                ),
              );
              setState(() {});
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      
      _section(
        context,
        title: 'ABOUT',
        icon: Icons.info,
        children: [
          _navRow(
            context,
            icon: Icons.info_outline,
            title: 'About WeAfrica Music',
            onTap: () => _open(context, const AboutWeAfricaMusicPage()),
          ),
          _navRow(
            context,
            icon: Icons.star_outline,
            title: 'Rate App',
            onTap: () async {
              final ok = await rateApp();
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open store page.')),
                );
              }
            },
          ),
          _actionRow(
            context,
            icon: Icons.logout,
            title: 'Log Out',
            action: _GoldPill(text: 'EXIT'),
            onTap: () => _handleLogout(context),
          ),
        ],
      ),
      
      if (DebugFlags.showDeveloperUi) ...[
        const SizedBox(height: 16),
        _section(
          context,
          title: 'DEVELOPER',
          icon: Icons.code,
          children: [
            _navRow(
              context,
              icon: Icons.graphic_eq,
              title: 'DJ Studio',
              subtitle: 'Open professional DJ deck controls',
              onTap: () => Navigator.of(context).pushNamed('/dj/studio'),
            ),
            _navRow(
              context,
              icon: Icons.notifications_active,
              title: 'Push token registration',
              subtitle: 'Verify backend URL + register',
              onTap: () => _open(context, const _PushTokenDebugScreen()),
            ),
            _actionRow(
              context,
              icon: Icons.key,
              title: 'Copy FCM token',
              subtitle: 'FirebaseMessaging token',
              action: _GoldPill(text: 'COPY'),
              onTap: () async {
                final token = await NotificationService.instance.getFcmToken();
                if (!mounted) return;

                if (token == null || token.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('FCM token unavailable'),
                    ),
                  );
                  return;
                }

                await Clipboard.setData(ClipboardData(text: token));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('FCM token copied'),
                    backgroundColor: _gold,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    ];
  }

  Widget _buildSubscriptionRow() {
    return AnimatedBuilder(
      animation: SubscriptionsController.instance,
      builder: (context, _) {
        final subController = SubscriptionsController.instance;
        final planId = subController.currentPlanId;
        final isActive = subController.isPremiumActive;
        final badgeText = _badgeTextForPlanId(planId);

        final plans = subController.plans;
        SubscriptionPlan? matched;
        for (final p in plans) {
          if (planIdMatches(p.planId, planId)) {
            matched = p;
            break;
          }
        }
          final displayName = (matched?.name ?? '').trim().isEmpty ? displayNameForPlanId(planId) : matched!.name;

        return _navRow(
          context,
          icon: Icons.credit_card,
          title: 'Subscription',
          subtitle: isActive ? 'Current: $displayName' : 'Current: $displayName (inactive)',
          badge: _GoldPill(text: badgeText),
          onTap: () => _open(context, RoleBasedSubscriptionScreen(roleOverride: _role)),
        );
      },
    );
  }

  bool _matchesQuery(Widget w) {
    if (_query.isEmpty) return true;
    if (w is _SectionCard) return w.matches(_query);
    return true;
  }

  Widget _section(BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return _SectionCard(
      title: title,
      icon: icon,
      query: _query,
      children: children,
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlassContainer(
            width: 320,
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
            child: SingleChildScrollView(
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
                    'LOG OUT?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Are you sure you want to log out?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackActions = constraints.maxWidth < 260;
                      if (stackActions) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('CANCEL'),
                            ),
                            const SizedBox(height: 12),
                            _LogoutConfirmButton(
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('CANCEL'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LogoutConfirmButton(
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await AuthActions.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  Widget _navRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? badge,
    required VoidCallback onTap,
  }) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: badge,
            ),
            const SizedBox(width: 10),
          ],
          Icon(Icons.chevron_right, color: _gold, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
    required VoidCallback onTap,
  }) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: action,
      onTap: onTap,
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: _gold,
        activeTrackColor: _gold.withAlpha(77),
      ),
      onTap: () => onChanged(!value),
    );
  }

  Widget _dropdownRow<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required T value,
    required List<T> values,
    required String Function(T) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1A1A28),
          icon: Icon(Icons.arrow_drop_down, color: _gold),
          style: const TextStyle(color: Colors.white),
          items: values
              .map(
                (v) => DropdownMenuItem<T>(
                  value: v,
                  child: Text(labelFor(v)),
                ),
              )
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    required this.query,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String query;

  static const Color _gold = Color(0xFFD4AF37);

  bool matches(String q) {
    final qq = q.trim().toLowerCase();
    if (qq.isEmpty) return true;
    if (title.toLowerCase().contains(qq)) return true;

    for (final c in children) {
      if (c is _SettingsRow) {
        if (c.title.toLowerCase().contains(qq)) return true;
        if ((c.subtitle ?? '').toLowerCase().contains(qq)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final visibleChildren = query.isEmpty
        ? children
        : children.where((c) {
            if (c is _SettingsRow) {
              final t = c.title.toLowerCase();
              final s = (c.subtitle ?? '').toLowerCase();
              return t.contains(query) || s.contains(query);
            }
            return true;
          }).toList(growable: false);

    if (visibleChildren.isEmpty) return const SizedBox.shrink();

    return GlassContainer(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        colors: [
          const Color(0xFF1A1A28).withAlpha(128),
          const Color(0xFF12121C).withAlpha(77),
        ],
      ),
      borderColor: _gold.withAlpha(51),
      blur: 15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _gold.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withAlpha(77)),
                ),
                child: Icon(icon, color: _gold, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._withDividers(visibleChildren),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(Divider(height: 18, color: _gold.withAlpha(26)));
      }
    }
    return out;
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: _gold.withAlpha(13),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withAlpha(51)),
              ),
              child: Icon(icon, size: 18, color: _gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(128),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Flexible(
                flex: 0,
                child: Align(
                  alignment: Alignment.topRight,
                  child: trailing,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoutConfirmButton extends StatelessWidget {
  const _LogoutConfirmButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.red, Color(0xFFFF6B6B)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        child: const Text('LOG OUT'),
      ),
    );
  }
}

class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withAlpha(26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD4AF37).withAlpha(77),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Color(0xFFD4AF37),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PushTokenDebugScreen extends StatefulWidget {
  const _PushTokenDebugScreen();

  @override
  State<_PushTokenDebugScreen> createState() => _PushTokenDebugScreenState();
}

class _PushTokenDebugScreenState extends State<_PushTokenDebugScreen> {
  bool _busy = false;
  String? _lastResult;
  String? _token;
  String? _permissionStatus;

  String _permissionSummary(NotificationSettings settings) {
    final parts = <String>[settings.authorizationStatus.name];
    if (settings.alert == AppleNotificationSetting.enabled) parts.add('alert');
    if (settings.badge == AppleNotificationSetting.enabled) parts.add('badge');
    if (settings.sound == AppleNotificationSetting.enabled) parts.add('sound');
    return parts.join(' | ');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDebugState());
  }

  Future<void> _refreshDebugState({bool refreshToken = false}) async {
    final service = NotificationService.instance;

    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final token = refreshToken
          ? await service.getFcmToken(refresh: true)
          : (service.fcmToken ?? await service.getFcmToken());

      if (!mounted) return;
      setState(() {
        _permissionStatus = _permissionSummary(settings);
        _token = token;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionStatus = 'error';
        _lastResult = 'Failed to load push diagnostics: $e';
      });
    }
  }

  Future<void> _copyToken() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No FCM token available to copy.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('FCM token copied.')),
    );
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (!mounted) return;
      setState(() {
        _permissionStatus = _permissionSummary(settings);
        _lastResult = 'Notification permission: ${settings.authorizationStatus.name}';
      });

      await _refreshDebugState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastResult = 'Failed to request notification permission: $e';
      });
    }
  }

  String _shortToken(String? token) {
    final value = (token ?? '').trim();
    if (value.isEmpty) return '(none yet)';
    if (value.length <= 24) return value;
    return '${value.substring(0, 12)}...${value.substring(value.length - 12)}';
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationService.instance;
    final effectiveBaseUrl = service.pushBackendBaseUrl;
    final definedApiBaseUrl = ApiEnv.definedBaseUrl;
    final user = FirebaseAuth.instance.currentUser;
    final token = _token ?? service.fcmToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push token debug'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoTile(
            title: 'Push service',
            value: effectiveBaseUrl.isEmpty ? '(not configured)' : effectiveBaseUrl,
          ),
          const SizedBox(height: 10),
          _infoTile(
            title: 'Service configuration',
            value: definedApiBaseUrl.isEmpty ? '(not configured)' : definedApiBaseUrl,
          ),
          const SizedBox(height: 10),
          _infoTile(
            title: 'Firebase user',
            value: user?.uid ?? '(not signed in)',
          ),
          const SizedBox(height: 10),
          _infoTile(
            title: 'Notification permission',
            value: _permissionStatus ?? '(loading)',
          ),
          const SizedBox(height: 10),
          _infoTile(
            title: 'Push token',
            value: _shortToken(token),
          ),
          if ((token ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoTile(
              title: 'Full token',
              value: token!.trim(),
              selectable: true,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _lastResult = null;
                          });
                          try {
                            await _refreshDebugState(refreshToken: true);
                            if (!mounted) return;
                            setState(() => _lastResult = 'FCM token refreshed.');
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('REFRESH TOKEN'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _copyToken,
                  child: const Text('COPY TOKEN'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _lastResult = null;
                    });
                    try {
                      await _requestPermission();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('REQUEST PERMISSION'),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4AF37), Color(0xFFF2D572)],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _lastResult = null;
                      });
                      try {
                        final messenger = ScaffoldMessenger.of(context);
                        final result = await service.registerDeviceTokenNow();
                        if (!mounted) return;
                        setState(() => _lastResult = result.message);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            backgroundColor: result.ok
                                ? const Color(0xFFD4AF37)
                                : Colors.red,
                          ),
                        );
                        await _refreshDebugState();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.black,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('REGISTER TOKEN'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: refresh the token first, then register it. If this is iOS and the token stays empty, check that GoogleService-Info.plist and push capability are configured.',
            style: TextStyle(color: Colors.white.withAlpha(128)),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 12),
            Text('Last result: $_lastResult'),
          ],
        ],
      ),
    );
  }

  Widget _infoTile({required String title, required String value, bool selectable = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37).withAlpha(51)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (selectable)
                  SelectableText(value, style: const TextStyle(color: Colors.white70))
                else
                  Text(value, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}