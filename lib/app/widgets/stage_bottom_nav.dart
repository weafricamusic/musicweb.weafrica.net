import 'package:flutter/material.dart';

import '../theme/weafrica_colors.dart';

class StageBottomNav extends StatelessWidget {
  const StageBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<StageNavItem>? items;

  @override
  Widget build(BuildContext context) {
    final navItems = items ?? const <StageNavItem>[
      StageNavItem(icon: Icons.home_rounded, label: 'Home'),
      StageNavItem(icon: Icons.live_tv_rounded, label: 'Live'),
      StageNavItem(icon: Icons.library_music_rounded, label: 'Library'),
      StageNavItem(icon: Icons.person_rounded, label: 'Profile'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: WeAfricaColors.surfaceDark.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(navItems.length, (index) {
            final item = navItems[index];
            final isActive = index == currentIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(index),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: isActive ? WeAfricaColors.gold : Colors.white54,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isActive ? WeAfricaColors.gold : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class StageNavItem {
  const StageNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
