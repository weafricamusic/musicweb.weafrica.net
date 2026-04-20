import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../../core/widgets/studio_card.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';
import 'dj_events_screen.dart';
import 'dj_earnings_screen.dart';
import 'dj_inbox_screen.dart';
import 'dj_live_battles_screen.dart';
import 'dj_sets_screen.dart';

class DjDashboardHomeScreen extends StatefulWidget {
  const DjDashboardHomeScreen({
    super.key,
    this.onSignOut,
    this.showAppBar = true,
    this.onUploadMix,
    this.onOpenMixes,
    this.onOpenBattles,
    this.onOpenEarnings,
    this.onOpenEvents,
    this.onOpenInbox,
  });

  final VoidCallback? onSignOut;
  final bool showAppBar;

  /// Optional in-shell navigation callbacks. When provided, the dashboard
  /// uses them instead of pushing new routes so the left menu stays visible.
  final VoidCallback? onUploadMix;
  final VoidCallback? onOpenMixes;
  final VoidCallback? onOpenBattles;
  final VoidCallback? onOpenEarnings;
  final VoidCallback? onOpenEvents;
  final VoidCallback? onOpenInbox;

  @override
  State<DjDashboardHomeScreen> createState() => _DjDashboardHomeScreenState();
}

class _DjDashboardHomeScreenState extends State<DjDashboardHomeScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<DjDashboardHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DjDashboardHomeData> _load() async {
    final uid = _identity.requireDjUid();
    return _service.loadHome(djUid: uid);
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String _formatMoney(num value) {
    final fixed = value.toStringAsFixed(2);
    if (fixed.endsWith('.00')) return value.toStringAsFixed(0);
    return fixed;
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<DjDashboardHomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(
            message: UserFacingError.message(
              snapshot.error,
              fallback: 'Could not load DJ dashboard data. Please try again.',
            ),
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return _ErrorState(
            message: 'No dashboard data available.',
            onRetry: () => setState(() {
              _future = _load();
            }),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HeroSection(),
              const SizedBox(height: 16),
              _StatsGrid(
                plays: data.totalPlays,
                followers: data.followersCount,
                earnings: data.totalEarnings,
                unread: data.unreadMessagesCount,
                formatMoney: _formatMoney,
              ),
              const SizedBox(height: 20),
              _QuickActions(
                onUploadMix: widget.onUploadMix ??
                    () => _open(context, const DjSetsScreen(autoOpenUpload: true)),
                onOpenBattles: widget.onOpenBattles ??
                    () => _open(context, const DjLiveBattlesScreen()),
                onOpenEarnings: widget.onOpenEarnings ??
                    () => _open(context, const DjEarningsScreen()),
              ),
              const SizedBox(height: 20),
              _EventsSection(
                upcomingLives: data.upcomingLives,
                onManage: widget.onOpenEvents ?? () => _open(context, const DjEventsScreen()),
              ),
              const SizedBox(height: 20),
              _NotificationsSection(
                recentInbox: data.recentInbox,
                onOpenInbox: widget.onOpenInbox ?? () => _open(context, const DjInboxScreen()),
              ),
              const SizedBox(height: 20),
              const _AIInsightsCard(),
              const SizedBox(height: 20),
              _RecentMixesSection(
                recentSets: data.recentSets,
                onOpenMixes: widget.onOpenMixes ?? () => _open(context, const DjSetsScreen()),
              ),
              const SizedBox(height: 20),
              _EarningsCard(
                totalEarningsLabel: _formatMoney(data.totalEarnings),
                coinBalanceLabel: data.coinBalance.toStringAsFixed(0),
                onWithdraw: widget.onOpenEarnings ?? () => _open(context, const DjEarningsScreen()),
              ),
              const SizedBox(height: 20),
              _BoostsSection(boostsCount: data.boostsCount),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('DJ Dashboard'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: body,
    );
  }
}

// ---------- Hero Section ----------
class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        colors: <Color>[
          AppColors.surface2,
          AppColors.stageGold.withValues(alpha: 0.14),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.person, color: AppColors.stageGold, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Welcome back',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ready to rock your fans today?',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------- Stats Grid ----------
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.plays,
    required this.followers,
    required this.earnings,
    required this.unread,
    required this.formatMoney,
  });

  final int plays;
  final int followers;
  final num earnings;
  final int unread;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w < 520
            ? 1
            : w < 950
                ? 2
                : w < 1200
                    ? 3
                    : 4;

        final aspect = crossAxisCount == 1 ? 2.2 : (crossAxisCount == 2 ? 1.25 : 1.55);

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
            StudioMetricCard(
              label: 'PLAYS',
              value: plays.toString(),
              icon: Icons.play_circle,
              tooltip: 'Total plays (best-effort)',
            ),
            StudioMetricCard(
              label: 'EARNINGS',
              value: '\$${formatMoney(earnings)}',
              icon: Icons.account_balance_wallet_outlined,
              tooltip: 'Total earnings (best-effort)',
            ),
            StudioMetricCard(
              label: 'FOLLOWERS',
              value: followers.toString(),
              icon: Icons.people,
              tooltip: 'Total followers',
            ),
            StudioMetricCard(
              label: 'UNREAD',
              value: unread.toString(),
              icon: Icons.notifications_none,
              tooltip: 'Unread messages/notifications',
            ),
          ],
        );
      },
    );
  }
}

// ---------- Quick Actions ----------
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onUploadMix,
    required this.onOpenBattles,
    required this.onOpenEarnings,
  });

  final VoidCallback onUploadMix;
  final VoidCallback onOpenBattles;
  final VoidCallback onOpenEarnings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final children = <Widget>[
          _ActionButton(
            icon: Icons.upload,
            label: 'Upload Mix',
            onTap: onUploadMix,
          ),
          _ActionButton(
            icon: Icons.sports_mma,
            label: 'Battles',
            onTap: onOpenBattles,
          ),
          _ActionButton(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Earnings',
            onTap: onOpenEarnings,
          ),
        ];

        if (narrow) {
          return Column(
            children: [
              for (final child in children) ...[
                SizedBox(width: double.infinity, child: child),
                if (child != children.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index < children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: StudioCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.stageGold),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- AI Insights ----------
class _AIInsightsCard extends StatelessWidget {
  const _AIInsightsCard();

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'AI Insights',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Unlock premium insights to see AI recommendations',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

String _fmtWhen(DateTime? dt) {
  if (dt == null) return 'TBA';
  final local = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} • ${two(local.hour)}:${two(local.minute)}';
}

// ---------- Events / Lives ----------
class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.upcomingLives,
    required this.onManage,
  });

  final List<DjEvent> upcomingLives;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Events',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: onManage,
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (upcomingLives.isEmpty)
            const Text('No scheduled live sessions yet.', style: TextStyle(color: AppColors.textMuted))
          else
            ...upcomingLives.take(3).map((e) {
              final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
              final when = '${_fmtWhen(e.startsAt)} → ${_fmtWhen(e.endsAt)}';
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: AppColors.stageGold, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ---------- Notifications ----------
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({
    required this.recentInbox,
    required this.onOpenInbox,
  });

  final List<DjMessage> recentInbox;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: onOpenInbox,
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentInbox.isEmpty)
            const Text('No recent messages.', style: TextStyle(color: AppColors.textMuted))
          else
            ...recentInbox.take(3).map((m) {
              final sender = (m.senderName ?? '').trim().isEmpty ? 'Message' : m.senderName!.trim();
              final body = m.content.trim().isEmpty ? '—' : m.content.trim();
              final unreadDot = m.isRead
                  ? const SizedBox(width: 10)
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.stageGold,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );

              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    unreadDot,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ---------- Recent mixes ----------
class _RecentMixesSection extends StatelessWidget {
  const _RecentMixesSection({
    required this.recentSets,
    required this.onOpenMixes,
  });

  final List<DjSet> recentSets;
  final VoidCallback onOpenMixes;

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent mixes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: onOpenMixes,
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentSets.isEmpty)
            const Text('No mixes uploaded yet.', style: TextStyle(color: AppColors.textMuted))
          else
            ...recentSets.take(4).map((s) {
              final parts = <String>[];
              final g = (s.genre ?? '').trim();
              if (g.isNotEmpty) parts.add(g);
              parts.add('${s.plays} plays');
              parts.add('${s.coinsEarned} coins');

              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.library_music, color: AppColors.stageGold, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            parts.join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ---------- Earnings ----------
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.totalEarningsLabel,
    required this.coinBalanceLabel,
    required this.onWithdraw,
  });

  final String totalEarningsLabel;
  final String coinBalanceLabel;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Earnings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text('Total earnings: $totalEarningsLabel'),
          const SizedBox(height: 6),
          Text('Coin balance: $coinBalanceLabel'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onWithdraw, child: const Text('Withdraw')),
        ],
      ),
    );
  }
}

// ---------- Boosts / Promotions ----------
class _BoostsSection extends StatelessWidget {
  const _BoostsSection({required this.boostsCount});

  final int boostsCount;

  @override
  Widget build(BuildContext context) {
    final boosts = boostsCount > 0
        ? List<String>.generate(boostsCount, (i) => 'Boost ${i + 1}')
        : const <String>['Boost Set 1', 'Boost Live 1'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Boosts / Promotions',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Column(
          children: boosts
              .map(
                (b) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: StudioCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            b,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: () {}, child: const Text('Boost')),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
