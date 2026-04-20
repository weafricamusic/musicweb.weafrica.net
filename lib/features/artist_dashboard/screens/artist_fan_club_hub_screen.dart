import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/artist_fan_club_models.dart';
import '../models/artist_subscription_tier.dart';
import '../services/artist_fan_club_service.dart';

class ArtistFanClubHubScreen extends StatefulWidget {
  const ArtistFanClubHubScreen({
    super.key,
    required this.artistName,
    required this.planSpec,
    required this.onManageSubscription,
  });

  final String artistName;
  final ArtistSubscriptionPlanSpec planSpec;
  final VoidCallback onManageSubscription;

  @override
  State<ArtistFanClubHubScreen> createState() => _ArtistFanClubHubScreenState();
}

class _ArtistFanClubHubScreenState extends State<ArtistFanClubHubScreen> {
  final _service = ArtistFanClubService();
  final _searchCtrl = TextEditingController();

  late Future<FanClubHubData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.loadHub();
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _service.loadHub();
    });
    await _future;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatMwk(num value) => 'MWK ${value.toStringAsFixed(0)}';

  String _formatCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  String _relative(DateTime? when) {
    if (when == null) return 'Recently';
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()} week${(diff.inDays / 7).floor() == 1 ? '' : 's'} ago';
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} min ago';
    return 'Just now';
  }

  Color _tierColor(String tierKey) {
    return switch (tierKey) {
      'vip' => const Color(0xFFD4AF37),
      'premium' => const Color(0xFF00B8A9),
      _ => const Color(0xFF8A8A8A),
    };
  }

  Future<void> _manageTier(FanClubTier tier) async {
    if (!widget.planSpec.canUseFanClub && tier.tierKey != 'free') {
      widget.onManageSubscription();
      return;
    }

    final result = await showModalBottomSheet<_TierFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111214),
      builder: (context) => _TierFormSheet(tier: tier),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await _service.updateTier(
        tier.copyWith(
          priceMwk: result.priceMwk,
          description: result.description,
          perks: result.perks,
          isActive: result.isActive,
        ),
      );
      _snack('${tier.title} updated.');
      await _refresh();
    } catch (_) {
      _snack('Could not update tier.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeFanTier(FanClubFan fan, String tierKey) async {
    if (!widget.planSpec.canUseFanClub && tierKey != 'free') {
      widget.onManageSubscription();
      return;
    }

    setState(() => _busy = true);
    try {
      await _service.setFanTier(fanUserId: fan.userId, tierKey: tierKey, current: fan);
      _snack('${fan.displayName} moved to ${tierKey.toUpperCase()}.');
      await _refresh();
    } catch (_) {
      _snack('Could not update fan tier.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createOrEditContent({FanClubContentItem? item}) async {
    if (!widget.planSpec.canUseFanClub) {
      widget.onManageSubscription();
      return;
    }

    final result = await showModalBottomSheet<_ContentFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111214),
      builder: (context) => _ContentFormSheet(item: item),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await _service.createOrUpdateContent(
        id: item?.id,
        title: result.title,
        description: result.description,
        contentType: result.contentType,
        accessTier: result.accessTier,
        mediaUrl: result.mediaUrl,
      );
      _snack(item == null ? 'Content created.' : 'Content updated.');
      await _refresh();
    } catch (_) {
      _snack('Could not save content.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteContent(FanClubContentItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete content?'),
        content: Text('Remove "${item.title}" from your Fan Club?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.deleteContent(item.id);
      _snack('Content deleted.');
      await _refresh();
    } catch (_) {
      _snack('Could not delete content.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendAnnouncement({String audience = 'all', String? recipientName}) async {
    if (!widget.planSpec.canUseFanClub) {
      widget.onManageSubscription();
      return;
    }

    final result = await showModalBottomSheet<_AnnouncementFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111214),
      builder: (context) => _AnnouncementFormSheet(initialAudience: audience, recipientName: recipientName),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await _service.sendAnnouncement(
        audience: result.audience,
        message: result.message,
        linkUrl: result.linkUrl,
        imageUrl: result.imageUrl,
      );
      _snack('Announcement sent.');
      await _refresh();
    } catch (_) {
      _snack('Could not send announcement.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReward({String audience = 'vip', List<String> recipientIds = const <String>[]}) async {
    if (!widget.planSpec.canUseFanClub) {
      widget.onManageSubscription();
      return;
    }

    final result = await showModalBottomSheet<_RewardFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111214),
      builder: (context) => _RewardFormSheet(initialAudience: audience),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await _service.sendReward(
        rewardType: result.rewardType,
        audience: result.audience,
        note: result.note,
        recipientIds: recipientIds,
      );
      _snack('Reward queued.');
      await _refresh();
    } catch (_) {
      _snack('Could not send reward.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<FanClubFan> _filterFans(List<FanClubFan> fans) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return fans;
    return fans.where((fan) {
      return fan.displayName.toLowerCase().contains(query) || fan.tierLabel.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final canUse = widget.planSpec.canUseFanClub;

    return Container(
      color: const Color(0xFF0A0A0C),
      child: FutureBuilder<FanClubHubData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _FanHubErrorState(onRetry: _refresh);
          }

          final data = snap.data;
          if (data == null) {
            return _FanHubErrorState(onRetry: _refresh);
          }

          final fans = _filterFans(data.fans);

          return RefreshIndicator(
            color: AppColors.brandOrange,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _HubHeader(
                  artistName: widget.artistName,
                  genre: data.artistGenre,
                  country: data.artistCountry,
                  fansCount: data.fansCount,
                  rating: data.averageRating,
                  onSettings: widget.onManageSubscription,
                ),
                const SizedBox(height: 14),
                _StatsGrid(
                  items: [
                    _StatTileData(label: 'FANS', value: _formatCount(data.fansCount), delta: '+${data.membersGrowthThisMonth} this month', icon: Icons.people_outline),
                    _StatTileData(label: 'FOLLOWERS', value: _formatCount(data.followersCount), delta: '+${data.followersGrowthThisMonth} this month', icon: Icons.wifi_tethering_outlined),
                    _StatTileData(label: 'CLUB EARNINGS', value: _formatMwk(data.clubEarningsMwk), delta: 'This month', icon: Icons.payments_outlined),
                    _StatTileData(label: 'VIP MEMBERS', value: _formatCount(data.vipMembersCount), delta: '+${data.vipGrowthThisMonth} this month', icon: Icons.workspace_premium_outlined),
                  ],
                ),
                const SizedBox(height: 18),
                if (!canUse)
                  _UpgradeBanner(onPressed: widget.onManageSubscription),
                const SizedBox(height: 18),
                _SectionShell(
                  title: 'Membership Tiers',
                  icon: Icons.workspace_premium_outlined,
                  child: Column(
                    children: [
                      for (final tier in data.tiers) ...[
                        _TierCard(
                          tier: tier,
                          onManage: () => _manageTier(tier),
                          accent: _tierColor(tier.tierKey),
                        ),
                        if (tier != data.tiers.last) const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionShell(
                  title: 'Fan Management',
                  icon: Icons.people_alt_outlined,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search fans...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFF141416),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2C2C30))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2C2C30))),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (fans.isEmpty)
                        const _EmptyState(
                          title: 'No fans yet',
                          subtitle: 'Followers will appear here once listeners start following your profile.',
                        )
                      else
                        for (final fan in fans.take(20)) ...[
                          _FanRow(
                            fan: fan,
                            accent: _tierColor(fan.tierKey),
                            onMessage: () => _sendAnnouncement(audience: 'custom', recipientName: fan.displayName),
                            onReward: () => _sendReward(audience: 'custom', recipientIds: [fan.userId]),
                            onChangeTier: (tierKey) => _changeFanTier(fan, tierKey),
                          ),
                          if (fan != fans.take(20).last) const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionShell(
                  title: 'Exclusive Content',
                  icon: Icons.lock_open_outlined,
                  action: FilledButton.icon(
                    onPressed: _busy ? null : () => _createOrEditContent(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                  child: data.contentItems.isEmpty
                      ? const _EmptyState(
                          title: 'No exclusive content yet',
                          subtitle: 'Create previews, behind-the-scenes posts, and VIP messages for your supporters.',
                        )
                      : Column(
                          children: [
                            for (final item in data.contentItems) ...[
                              _ContentRow(
                                item: item,
                                onAnalytics: () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(item.title),
                                      content: Text('Views/plays: ${item.playsCount}\nComments: ${item.commentsCount}\nAudience: ${item.accessTier.toUpperCase()}'),
                                      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
                                    ),
                                  );
                                },
                                onEdit: () => _createOrEditContent(item: item),
                                onDelete: () => _deleteContent(item),
                              ),
                              if (item != data.contentItems.last) const SizedBox(height: 12),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                _SectionShell(
                  title: 'Fan Analytics',
                  icon: Icons.insights_outlined,
                  child: Column(
                    children: [
                      _AnalyticsGrowthCard(growthDelta: data.analytics.growthDelta),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 720) {
                            return Column(
                              children: [
                                _AnalyticsListCard(title: 'Top Gift Givers', rows: data.analytics.topGifters, kind: _AnalyticsKind.gifts),
                                const SizedBox(height: 12),
                                _AnalyticsListCard(title: 'Top Spenders', rows: data.analytics.topSpenders, kind: _AnalyticsKind.spend),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: _AnalyticsListCard(title: 'Top Gift Givers', rows: data.analytics.topGifters, kind: _AnalyticsKind.gifts)),
                              const SizedBox(width: 12),
                              Expanded(child: _AnalyticsListCard(title: 'Top Spenders', rows: data.analytics.topSpenders, kind: _AnalyticsKind.spend)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _EngagementCard(
                        comments: data.analytics.commentsCount,
                        likes: data.analytics.likesCount,
                        shares: data.analytics.sharesCount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionShell(
                  title: 'Engage Fans',
                  icon: Icons.campaign_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _sendAnnouncement(),
                            icon: const Icon(Icons.notifications_active_outlined),
                            label: const Text('Send Announcement'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _sendReward(),
                            icon: const Icon(Icons.card_giftcard_outlined),
                            label: const Text('Send Rewards'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (data.announcements.isNotEmpty) ...[
                        const Text('Recent announcements', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        for (final item in data.announcements.take(3)) ...[
                          _SimpleFeedRow(
                            icon: Icons.announcement_outlined,
                            title: item.message,
                            subtitle: '${item.audience.toUpperCase()} • ${_relative(item.sentAt)}',
                          ),
                          if (item != data.announcements.take(3).last) const SizedBox(height: 10),
                        ],
                      ],
                      if (data.rewards.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text('Recent rewards', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        for (final item in data.rewards.take(3)) ...[
                          _SimpleFeedRow(
                            icon: Icons.redeem_outlined,
                            title: item.rewardType.replaceAll('_', ' ').toUpperCase(),
                            subtitle: '${item.audience.toUpperCase()} • ${item.recipientsCount} recipients • ${_relative(item.createdAt)}',
                          ),
                          if (item != data.rewards.take(3).last) const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.artistName,
    required this.genre,
    required this.country,
    required this.fansCount,
    required this.rating,
    required this.onSettings,
  });

  final String artistName;
  final String genre;
  final String country;
  final int fansCount;
  final double rating;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('FAN CLUB', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              IconButton(onPressed: onSettings, icon: const Icon(Icons.settings_outlined)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF1B1D22), Color(0xFF111214)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF2C2C30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artistName.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('🎵 $genre • $country', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text('📊 ${fansCount.toString()} Fans  •  🎖️ ${rating.toStringAsFixed(1)} Rating', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.items});

  final List<_StatTileData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 720 ? 2 : 4;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, color: AppColors.brandOrange),
                      const SizedBox(height: 10),
                      Text(item.label, style: const TextStyle(color: Color(0xFFA0A0A0), fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(item.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(item.delta, style: const TextStyle(color: Color(0xFFA0A0A0), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      gradient: const LinearGradient(
        colors: [Color(0xFF261B00), Color(0xFF17130B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderColor: const Color(0xFF8F6B00),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fan Club unlocks on Artist Premium', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                  'Upgrade to manage exclusive tiers, post member-only content, and build a loyal paid community.',
                  style: TextStyle(color: Color(0xFFE6D7A6), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onPressed, child: const Text('Upgrade')),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.brandOrange),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              ?action,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.onManage, required this.accent});

  final FanClubTier tier;
  final VoidCallback onManage;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final priceLabel = tier.priceMwk <= 0 ? '' : 'MWK ${tier.priceMwk}/month';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.18), const Color(0xFF141416)]),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${_tierEmoji(tier.tierKey)} ${tier.title}${priceLabel.isEmpty ? '' : '    $priceLabel'}', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Text('[${tier.memberCount} members]', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final perk in tier.perks) ...[
            Text('• $perk', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(onPressed: onManage, child: const Text('Manage')),
              const SizedBox(width: 12),
              Text(tier.isActive ? 'ACTIVE' : 'PAUSED', style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanRow extends StatelessWidget {
  const _FanRow({
    required this.fan,
    required this.accent,
    required this.onMessage,
    required this.onReward,
    required this.onChangeTier,
  });

  final FanClubFan fan;
  final Color accent;
  final VoidCallback onMessage;
  final VoidCallback onReward;
  final ValueChanged<String> onChangeTier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.withValues(alpha: 0.20),
                backgroundImage: fan.avatarUrl == null ? null : NetworkImage(fan.avatarUrl!),
                child: fan.avatarUrl == null ? Text(fan.displayName.substring(0, 1).toUpperCase()) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fan.displayName, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${_tierEmoji(fan.tierKey)} ${fan.tierLabel} • Joined ${_joinedLabel(fan.joinedAt)}', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('💰 MWK ${fan.totalSpentMwk.toStringAsFixed(0)} total spent', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('🎁 ${fan.giftsSent} gifts sent • ${fan.comments} comments', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onMessage, child: const Text('Message')),
              OutlinedButton(onPressed: onReward, child: const Text('Send Gift')),
              PopupMenuButton<String>(
                onSelected: onChangeTier,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'free', child: Text('Set Free')),
                  PopupMenuItem(value: 'premium', child: Text('Set Premium')),
                  PopupMenuItem(value: 'vip', child: Text('Set VIP')),
                ],
                child: FilledButton(
                  onPressed: null,
                  child: Text(
                    fan.tierKey == 'vip' ? 'VIP' : fan.tierKey == 'premium' ? 'Upgrade' : 'Offer',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _joinedLabel(DateTime? when) {
    if (when == null) return 'recently';
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'}';
    }
    if (diff.inDays >= 7) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'}';
    }
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    return 'today';
  }
}

class _ContentRow extends StatelessWidget {
  const _ContentRow({
    required this.item,
    required this.onAnalytics,
    required this.onEdit,
    required this.onDelete,
  });

  final FanClubContentItem item;
  final VoidCallback onAnalytics;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_contentEmoji(item.contentType)} ${item.title}', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('Only for ${item.accessTier == 'free' ? 'all members' : '${item.accessTier.toUpperCase()}+ members'}', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Posted: ${_when(item.publishedAt)}', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('🔥 ${item.playsCount} plays • 💬 ${item.commentsCount} comments', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onAnalytics, child: const Text('Analytics')),
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              OutlinedButton(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime? date) {
    if (date == null) return 'Recently';
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    return '${diff.inMinutes.clamp(0, 59)} min ago';
  }
}

enum _AnalyticsKind { gifts, spend }

class _AnalyticsGrowthCard extends StatelessWidget {
  const _AnalyticsGrowthCard({required this.growthDelta});

  final int growthDelta;

  @override
  Widget build(BuildContext context) {
    final normalized = ((growthDelta + 50) / 100).clamp(0.08, 1.0);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MEMBERSHIP GROWTH', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 12,
              color: AppColors.brandOrange,
              backgroundColor: const Color(0xFF242428),
            ),
          ),
          const SizedBox(height: 10),
          Text('${growthDelta >= 0 ? '+' : ''}$growthDelta this month', style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AnalyticsListCard extends StatelessWidget {
  const _AnalyticsListCard({required this.title, required this.rows, required this.kind});

  final String title;
  final List<FanClubFan> rows;
  final _AnalyticsKind kind;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('No data yet.', style: TextStyle(color: Color(0xFFB5B5B5)))
          else
            for (final row in rows) ...[
              Row(
                children: [
                  Expanded(child: Text(row.displayName, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(
                    kind == _AnalyticsKind.gifts ? '${row.giftsSent} gifts' : 'MWK ${row.totalSpentMwk.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (row != rows.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _EngagementCard extends StatelessWidget {
  const _EngagementCard({required this.comments, required this.likes, required this.shares});

  final int comments;
  final int likes;
  final int shares;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ENGAGEMENT', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text('Comments: $comments', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Likes: $likes', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Shares: $shares', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SimpleFeedRow extends StatelessWidget {
  const _SimpleFeedRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.brandOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFFB5B5B5), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.gradient, this.borderColor});

  final Widget child;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gradient == null ? const Color(0xFF101114) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? const Color(0xFF2C2C30)),
      ),
      child: child,
    );
  }
}

class _FanHubErrorState extends StatelessWidget {
  const _FanHubErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            const Text('Could not load Fan Club.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _StatTileData {
  const _StatTileData({required this.label, required this.value, required this.delta, required this.icon});

  final String label;
  final String value;
  final String delta;
  final IconData icon;
}

class _TierFormData {
  const _TierFormData({required this.priceMwk, required this.description, required this.perks, required this.isActive});

  final int priceMwk;
  final String description;
  final List<String> perks;
  final bool isActive;
}

class _TierFormSheet extends StatefulWidget {
  const _TierFormSheet({required this.tier});

  final FanClubTier tier;

  @override
  State<_TierFormSheet> createState() => _TierFormSheetState();
}

class _TierFormSheetState extends State<_TierFormSheet> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _perksCtrl;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.tier.priceMwk.toString());
    _descCtrl = TextEditingController(text: widget.tier.description);
    _perksCtrl = TextEditingController(text: widget.tier.perks.join('\n'));
    _isActive = widget.tier.isActive;
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _perksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Manage ${widget.tier.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly price (MWK)')),
          const SizedBox(height: 10),
          TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 10),
          TextField(controller: _perksCtrl, maxLines: 6, decoration: const InputDecoration(labelText: 'Perks (one per line)')),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            title: const Text('Tier active'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _TierFormData(
                    priceMwk: int.tryParse(_priceCtrl.text.trim()) ?? 0,
                    description: _descCtrl.text.trim(),
                    perks: _perksCtrl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false),
                    isActive: _isActive,
                  ),
                );
              },
              child: const Text('Save tier'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentFormData {
  const _ContentFormData({required this.title, required this.description, required this.contentType, required this.accessTier, required this.mediaUrl});

  final String title;
  final String description;
  final String contentType;
  final String accessTier;
  final String? mediaUrl;
}

class _ContentFormSheet extends StatefulWidget {
  const _ContentFormSheet({this.item});

  final FanClubContentItem? item;

  @override
  State<_ContentFormSheet> createState() => _ContentFormSheetState();
}

class _ContentFormSheetState extends State<_ContentFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _mediaCtrl;
  late String _contentType;
  late String _accessTier;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item?.title ?? '');
    _descCtrl = TextEditingController(text: widget.item?.description ?? '');
    _mediaCtrl = TextEditingController(text: widget.item?.mediaUrl ?? '');
    _contentType = widget.item?.contentType ?? 'message';
    _accessTier = widget.item?.accessTier ?? 'premium';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _mediaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.item == null ? 'Create Content' : 'Edit Content', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 10),
          TextField(controller: _descCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _contentType,
            items: const [
              DropdownMenuItem(value: 'song', child: Text('Song preview')),
              DropdownMenuItem(value: 'video', child: Text('Video')),
              DropdownMenuItem(value: 'message', child: Text('Message')),
              DropdownMenuItem(value: 'image', child: Text('Image')),
              DropdownMenuItem(value: 'audio', child: Text('Audio')),
            ],
            onChanged: (v) => setState(() => _contentType = v ?? _contentType),
            decoration: const InputDecoration(labelText: 'Content type'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _accessTier,
            items: const [
              DropdownMenuItem(value: 'free', child: Text('All members')),
              DropdownMenuItem(value: 'premium', child: Text('Premium+')),
              DropdownMenuItem(value: 'vip', child: Text('VIP only')),
            ],
            onChanged: (v) => setState(() => _accessTier = v ?? _accessTier),
            decoration: const InputDecoration(labelText: 'Access tier'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _mediaCtrl, decoration: const InputDecoration(labelText: 'Media URL (optional)')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _ContentFormData(
                    title: _titleCtrl.text.trim(),
                    description: _descCtrl.text.trim(),
                    contentType: _contentType,
                    accessTier: _accessTier,
                    mediaUrl: _mediaCtrl.text.trim().isEmpty ? null : _mediaCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Save content'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementFormData {
  const _AnnouncementFormData({required this.audience, required this.message, required this.linkUrl, required this.imageUrl});

  final String audience;
  final String message;
  final String? linkUrl;
  final String? imageUrl;
}

class _AnnouncementFormSheet extends StatefulWidget {
  const _AnnouncementFormSheet({required this.initialAudience, this.recipientName});

  final String initialAudience;
  final String? recipientName;

  @override
  State<_AnnouncementFormSheet> createState() => _AnnouncementFormSheetState();
}

class _AnnouncementFormSheetState extends State<_AnnouncementFormSheet> {
  late String _audience;
  final _messageCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _audience = widget.initialAudience;
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _linkCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.recipientName == null ? 'Send Announcement' : 'Message ${widget.recipientName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _audience,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All fans')),
              DropdownMenuItem(value: 'premium', child: Text('Premium members')),
              DropdownMenuItem(value: 'vip', child: Text('VIP members')),
              DropdownMenuItem(value: 'active_30d', child: Text('Active last 30 days')),
              DropdownMenuItem(value: 'custom', child: Text('Custom selection')),
            ],
            onChanged: (v) => setState(() => _audience = v ?? _audience),
            decoration: const InputDecoration(labelText: 'Audience'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _messageCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
          const SizedBox(height: 10),
          TextField(controller: _linkCtrl, decoration: const InputDecoration(labelText: 'Link (optional)')),
          const SizedBox(height: 10),
          TextField(controller: _imageCtrl, decoration: const InputDecoration(labelText: 'Image URL (optional)')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _AnnouncementFormData(
                    audience: _audience,
                    message: _messageCtrl.text.trim(),
                    linkUrl: _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
                    imageUrl: _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Send notification'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardFormData {
  const _RewardFormData({required this.rewardType, required this.audience, required this.note});

  final String rewardType;
  final String audience;
  final String note;
}

class _RewardFormSheet extends StatefulWidget {
  const _RewardFormSheet({required this.initialAudience});

  final String initialAudience;

  @override
  State<_RewardFormSheet> createState() => _RewardFormSheetState();
}

class _RewardFormSheetState extends State<_RewardFormSheet> {
  late String _rewardType;
  late String _audience;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rewardType = 'coins';
    _audience = widget.initialAudience;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Send Rewards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _rewardType,
            items: const [
              DropdownMenuItem(value: 'coins', child: Text('Free coins')),
              DropdownMenuItem(value: 'exclusive_content', child: Text('Exclusive content')),
              DropdownMenuItem(value: 'merch_discount', child: Text('Merch discount')),
              DropdownMenuItem(value: 'shoutout', child: Text('Shoutout')),
            ],
            onChanged: (v) => setState(() => _rewardType = v ?? _rewardType),
            decoration: const InputDecoration(labelText: 'Reward type'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _audience,
            items: const [
              DropdownMenuItem(value: 'top_gifters', child: Text('Top 10 gifters')),
              DropdownMenuItem(value: 'top_commenters', child: Text('Top 10 commenters')),
              DropdownMenuItem(value: 'vip', child: Text('All VIP members')),
              DropdownMenuItem(value: 'custom', child: Text('Custom selection')),
            ],
            onChanged: (v) => setState(() => _audience = v ?? _audience),
            decoration: const InputDecoration(labelText: 'Select fans'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _noteCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Reward note')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(_RewardFormData(rewardType: _rewardType, audience: _audience, note: _noteCtrl.text.trim()));
              },
              child: const Text('Send rewards'),
            ),
          ),
        ],
      ),
    );
  }
}

String _tierEmoji(String tierKey) {
  return switch (tierKey) {
    'vip' => '👑',
    'premium' => '💎',
    _ => '🌟',
  };
}

String _contentEmoji(String type) {
  return switch (type) {
    'song' => '🎵',
    'video' => '🎥',
    'image' => '🖼️',
    'audio' => '🎧',
    _ => '📝',
  };
}