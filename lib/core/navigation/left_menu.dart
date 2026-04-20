import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/auth/auth_actions.dart';
import 'menu_items.dart';

enum LeftMenuHeaderVariant {
  logo,
  profile,
}

class LeftMenuUpgradeConfig {
  const LeftMenuUpgradeConfig({
    required this.planName,
    required this.onUpgrade,
    this.titleLabel = 'CURRENT PLAN',
    this.ctaLabel = 'Go Premium',
    this.features = const <String>[],
  });

  final String titleLabel;
  final String planName;
  final String ctaLabel;
  final List<String> features;
  final VoidCallback onUpgrade;
}

class LeftMenu extends StatefulWidget {
  const LeftMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.items = MenuItems.items,
    this.width = 260,
    this.badges = const <int, String?>{},
    this.userName = 'Artist',
    this.userStatusLabel = 'Online',
    this.onLogout,
    this.headerVariant = LeftMenuHeaderVariant.logo,
    this.logoSubtitle = 'STUDIO',
    this.userSubtitle,
    this.userAvatarUrl,
    this.onViewProfile,
    this.upgrade,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<MenuItem> items;
  final double width;
  final Map<int, String?> badges;
  final String userName;
  final String userStatusLabel;
  final VoidCallback? onLogout;

  final LeftMenuHeaderVariant headerVariant;
  final String logoSubtitle;
  final String? userSubtitle;
  final String? userAvatarUrl;
  final VoidCallback? onViewProfile;
  final LeftMenuUpgradeConfig? upgrade;

  @override
  State<LeftMenu> createState() => _LeftMenuState();
}

class _LeftMenuState extends State<LeftMenu> {
  final Set<int> _expanded = <int>{};

  bool _containsSelected(MenuItem item) {
    if (item.index == widget.selectedIndex) return true;
    for (final child in item.children) {
      if (_containsSelected(child)) return true;
    }
    return false;
  }

  bool _isExpanded(MenuItem item) {
    if (item.children.isEmpty) return false;
    if (_containsSelected(item)) return true;
    return _expanded.contains(item.index);
  }

  void _toggle(MenuItem item) {
    if (item.children.isEmpty) return;

    setState(() {
      final next = !_expanded.contains(item.index);
      if (next) {
        _expanded.add(item.index);
      } else {
        _expanded.remove(item.index);
      }
    });
  }

  List<Widget> _buildMenuWidgets(List<MenuItem> items, {double indent = 0, bool compact = false}) {
    final widgets = <Widget>[];

    for (final item in items) {
      final hasChildren = item.children.isNotEmpty;

      if (!hasChildren) {
        final enabled = item.enabled && item.selectable;
        widgets.add(
          _MenuRow(
            item: item,
            isSelected: widget.selectedIndex == item.index,
            badge: widget.badges[item.index],
            onTap: enabled ? () => widget.onItemSelected(item.index) : null,
            indent: indent,
            compact: compact,
            enabled: item.enabled,
          ),
        );
        continue;
      }

      final expanded = _isExpanded(item);
      final enabled = item.enabled;
      final isSelected = _containsSelected(item);

      widgets.add(
        _MenuRow(
          item: item,
          isSelected: isSelected,
          badge: null,
          onTap: !enabled
              ? null
              : () {
                  _toggle(item);
                  if (item.selectable) {
                    widget.onItemSelected(item.index);
                  }
                },
          indent: indent,
          compact: compact,
          enabled: enabled,
          trailing: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              Icons.expand_more,
              size: compact ? 18 : 20,
              color: isSelected ? AppColors.stageGold : AppColors.textMuted,
            ),
          ),
        ),
      );

      if (expanded) {
        widgets.addAll(
          _buildMenuWidgets(
            item.children,
            indent: indent + 14,
            compact: true,
          ),
        );
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      color: AppColors.surface,
      child: Column(
        children: [
          switch (widget.headerVariant) {
            LeftMenuHeaderVariant.logo => _LogoHeader(subtitle: widget.logoSubtitle),
            LeftMenuHeaderVariant.profile => _ProfileHeader(
                userName: widget.userName,
                userSubtitle: widget.userSubtitle,
                userStatusLabel: widget.userStatusLabel,
                userAvatarUrl: widget.userAvatarUrl,
                onViewProfile: widget.onViewProfile,
              ),
          },
          Container(
            height: 1,
            color: AppColors.border,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ..._buildMenuWidgets(widget.items),
                if (widget.upgrade != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: _UpgradeCard(config: widget.upgrade!),
                  ),
                ],
              ],
            ),
          ),
          _UserFooter(
            userName: widget.userName,
            userStatusLabel: widget.userStatusLabel,
            onLogout: widget.onLogout,
          ),
        ],
      ),
    );
  }
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.stageGold,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'W',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'WEAFRICA',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.stageGold,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.trailing,
    this.indent = 0,
    this.compact = false,
    this.enabled = true,
  });

  final MenuItem item;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? badge;
  final Widget? trailing;
  final double indent;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final badgeValue = (badge ?? '').trim();

    final effectiveEnabled = enabled && onTap != null;
    final baseTextColor = isSelected ? AppColors.stageGold : AppColors.textMuted;
    final textColor = effectiveEnabled ? baseTextColor : AppColors.textMuted.withValues(alpha: 0.55);
    final iconColor = effectiveEnabled ? (isSelected ? AppColors.stageGold : AppColors.textMuted) : AppColors.textMuted.withValues(alpha: 0.55);

    return InkWell(
      onTap: effectiveEnabled ? onTap : null,
      child: Container(
        margin: EdgeInsets.fromLTRB(16 + indent, 4, 16, 4),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.stageGold.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: AppColors.stageGold.withValues(alpha: 0.28)) : null,
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: compact ? 18 : 20,
              color: iconColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: textColor,
                    ),
              ),
            ),
            if (badgeValue.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.stageGold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeValue,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),

            if (trailing != null) ...[
              if (badgeValue.isNotEmpty) const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.userName,
    required this.userStatusLabel,
    this.userSubtitle,
    this.userAvatarUrl,
    this.onViewProfile,
  });

  final String userName;
  final String userStatusLabel;
  final String? userSubtitle;
  final String? userAvatarUrl;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final subtitle = (userSubtitle ?? '').trim();
    final avatarUrl = (userAvatarUrl ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surface2,
                backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
                child: avatarUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColors.stageGold)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.brandBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          userStatusLabel,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onViewProfile != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onViewProfile,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View public profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.stageGold,
                side: BorderSide(color: AppColors.stageGold.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.config});

  final LeftMenuUpgradeConfig config;

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_outline, size: 16, color: AppColors.stageGold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.titleLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            config.planName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900, color: AppColors.stageGold),
          ),
          if (config.features.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final f in config.features) _bullet(f),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: config.onUpgrade,
              child: Text(config.ctaLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.userName,
    required this.userStatusLabel,
    this.onLogout,
  });

  final String userName;
  final String userStatusLabel;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.stageGold.withValues(alpha: 0.65)),
            ),
            child: const Icon(Icons.person, color: AppColors.stageGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      userStatusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 18),
            color: AppColors.textMuted,
            onPressed: () {
              final handler = onLogout;
              if (handler != null) {
                handler();
                return;
              }

              AuthActions.signOut();
            },
          ),
        ],
      ),
    );
  }
}
