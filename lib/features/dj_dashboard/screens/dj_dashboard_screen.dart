import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/theme.dart';
import '../../../core/navigation/left_menu.dart';
import '../../../core/navigation/menu_items.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../settings/creator_settings_screen.dart';
import '../../settings/creator_support_about_screen.dart';
import '../../auth/auth_actions.dart';
import '../../studio/screens/creator_pulse_uploads_screen.dart';
import '../../auth/user_role.dart';
import 'dj_dashboard_home_screen.dart';
import 'dj_earnings_screen.dart';
import 'dj_events_screen.dart';
import 'dj_boosts_screen.dart';
import 'dj_battle_history_screen.dart';
import 'dj_collaborations_screen.dart';
import 'dj_highlights_screen.dart';
import 'dj_leaderboards_screen.dart';
import 'dj_fans_screen.dart';
import 'dj_go_live_screen.dart';
import 'dj_inbox_screen.dart';
import 'dj_live_battles_screen.dart';
import 'dj_profile_screen.dart';
import 'dj_sets_screen.dart';
import 'dj_stats_screen.dart';

class DjDashboardScreen extends StatefulWidget {
  const DjDashboardScreen({super.key});

  @override
  State<DjDashboardScreen> createState() => _DjDashboardScreenState();
}

class _DjDashboardScreenState extends State<DjDashboardScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();

    // Keep subscription state fresh so creator dashboards unlock immediately
    // after an admin activates a plan.
    SubscriptionsController.instance.initialize();
    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(SubscriptionsController.instance.refreshMe());
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthActions.signOut();
    } catch (_) {
      // Best-effort: AuthGate will still typically update.
    }
  }

  void _setIndex(int index, {bool closeDrawer = false}) {
    if (!mounted) return;
    setState(() => _index = index);
    if (closeDrawer) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SubscriptionsController.instance,
      builder: (BuildContext context, Widget? _) {
        final isDesktop = ResponsiveLayout.isDesktop(context);

        final displayName = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
        final userName = displayName.isNotEmpty ? displayName : 'DJ';

        final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
        final subtitle = email.isNotEmpty ? email : 'DJ Studio';
        final avatarUrl = (FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();

    const menuItems = <MenuItem>[
      MenuItem(index: 0, title: 'DASHBOARD', icon: Icons.dashboard_outlined),

      MenuItem(
        index: -1,
        title: 'DJ STUDIO',
        icon: Icons.radio_outlined,
        selectable: false,
        children: <MenuItem>[
          MenuItem(index: 10, title: 'GO LIVE', icon: Icons.wifi_tethering),
          MenuItem(index: 4, title: 'SCHEDULE', icon: Icons.event_outlined),
          MenuItem(index: 1, title: 'MY MIXES', icon: Icons.library_music_outlined),
          MenuItem(index: 2, title: 'MY VIDEOS', icon: Icons.video_library_outlined),
          MenuItem(index: 9, title: 'STUDIO SETTINGS', icon: Icons.settings_outlined),
        ],
      ),

      MenuItem(
        index: -2,
        title: 'BATTLES',
        icon: Icons.sports_mma_outlined,
        selectable: false,
        children: <MenuItem>[
          MenuItem(index: 3, title: 'ACTIVE BATTLES', icon: Icons.sports_mma_outlined),
          MenuItem(index: 11, title: 'CREATE BATTLE', icon: Icons.person_add_alt_1_outlined),
          MenuItem(index: 12, title: 'BATTLE HISTORY', icon: Icons.history),
        ],
      ),

      MenuItem(
        index: -3,
        title: 'COMMUNITY',
        icon: Icons.people_outline,
        selectable: false,
        children: <MenuItem>[
          MenuItem(index: 13, title: 'FAN CLUB', icon: Icons.favorite_border),
          MenuItem(index: 14, title: 'COLLABORATIONS', icon: Icons.group_work_outlined),
          MenuItem(index: 7, title: 'INBOX', icon: Icons.notifications_none),
          MenuItem(index: 8, title: 'PUBLIC PROFILE', icon: Icons.person_outline),
        ],
      ),

      MenuItem(
        index: -4,
        title: 'INSIGHTS',
        icon: Icons.insights_outlined,
        selectable: false,
        children: <MenuItem>[
          MenuItem(index: 5, title: 'ANALYTICS', icon: Icons.query_stats_outlined),
          MenuItem(index: 6, title: 'EARNINGS', icon: Icons.payments_outlined),
          MenuItem(index: 17, title: 'BOOSTS', icon: Icons.campaign_outlined),
          MenuItem(index: 15, title: 'HIGHLIGHTS', icon: Icons.auto_awesome_outlined),
          MenuItem(index: 16, title: 'LEADERBOARDS', icon: Icons.emoji_events_outlined),
        ],
      ),

      MenuItem(index: 18, title: 'HELP & SUPPORT', icon: Icons.help_outline),
    ];

    final screens = <Widget>[
      DjDashboardHomeScreen(
        showAppBar: false,
        onUploadMix: () => _setIndex(1),
        onOpenMixes: () => _setIndex(1),
        onOpenBattles: () => _setIndex(3),
        onOpenEarnings: () => _setIndex(6),
        onOpenEvents: () => _setIndex(4),
        onOpenInbox: () => _setIndex(7),
      ),
      const DjSetsScreen(showAppBar: false),
      const CreatorPulseUploadsScreen(showAppBar: false, uploadIntent: UserRole.dj),
      const DjLiveBattlesScreen(showAppBar: false),
      const DjEventsScreen(showAppBar: false),
      const DjStatsScreen(showAppBar: false),
      const DjEarningsScreen(showAppBar: false),
      const DjInboxScreen(showAppBar: false),
      const DjProfileScreen(showAppBar: false),
      const CreatorSettingsScreen(showAppBar: false),

      DjGoLiveScreen(showAppBar: false),
      const DjLiveBattlesScreen(showAppBar: false),
      const DjBattleHistoryScreen(showAppBar: false),
      const DjFansScreen(showAppBar: false),
      const DjCollaborationsScreen(showAppBar: false),
      const DjHighlightsScreen(showAppBar: false),
      const DjLeaderboardsScreen(showAppBar: false),
      const DjBoostsScreen(showAppBar: false),
      const CreatorSupportAboutScreen(showAppBar: false),
    ];

    final clampedIndex = _index.clamp(0, screens.length - 1);
    String titleForIndex(int idx, List<MenuItem> list) {
      for (final it in list) {
        if (it.index == idx) return it.title;
        if (it.children.isNotEmpty) {
          final t = titleForIndex(idx, it.children);
          if (t.isNotEmpty) return t;
        }
      }
      return '';
    }

    final title = titleForIndex(clampedIndex, menuItems).trim().isEmpty
        ? 'DJ'
        : titleForIndex(clampedIndex, menuItems);

        final menu = LeftMenu(
          selectedIndex: clampedIndex,
          onItemSelected: (i) => _setIndex(i, closeDrawer: !isDesktop),
          items: menuItems,
          userName: userName,
          userStatusLabel: 'Online',
          onLogout: _signOut,

          headerVariant: LeftMenuHeaderVariant.profile,
          userSubtitle: subtitle,
          userAvatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
          onViewProfile: () => _setIndex(8, closeDrawer: !isDesktop),
          upgrade: null,
        );

        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                menu,
                Container(width: 1, height: double.infinity, color: AppColors.border),
                Expanded(child: screens[clampedIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'Inbox',
                onPressed: () => _setIndex(7),
                icon: const Icon(Icons.notifications_none),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => _setIndex(8),
                icon: const Icon(Icons.person_outline),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _setIndex(9),
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                tooltip: 'Logout',
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(child: menu),
          ),
          body: screens[clampedIndex],
        );
      },
    );
  }
}
