import 'package:flutter/material.dart';

import '../theme/weafrica_colors.dart';

class ModernBottomNavBar extends StatelessWidget {
  const ModernBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            WeAfricaColors.surfaceDark.withValues(alpha: 0.9),
            WeAfricaColors.surfaceDark,
          ],
        ),
        border: const Border(
          top: BorderSide(color: WeAfricaColors.gold, width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: WeAfricaColors.gold,
        unselectedItemColor: Colors.white54,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note_outlined),
            activeIcon: Icon(Icons.music_note),
            label: 'MUSIC',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.live_tv_outlined),
            activeIcon: Icon(Icons.live_tv),
            label: 'LIVE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_outlined),
            activeIcon: Icon(Icons.library_music),
            label: 'LIBRARY',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'PROFILE',
          ),
        ],
      ),
    );
  }
}
