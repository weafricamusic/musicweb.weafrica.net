import 'package:flutter/material.dart';

class MenuItem {
  const MenuItem({
    required this.index,
    required this.title,
    required this.icon,
    this.children = const <MenuItem>[],
    this.selectable = true,
    this.enabled = true,
  });

  final int index;
  final String title;
  final IconData icon;

  /// Optional nested menu items.
  ///
  /// When present, `LeftMenu` can render an expandable group.
  final List<MenuItem> children;

  /// Whether this item should trigger selection when tapped.
  ///
  /// For group rows (items with `children`), set this to false to make the row
  /// expand/collapse only.
  final bool selectable;

  /// Whether this menu item is enabled.
  ///
  /// Disabled items render muted and do not trigger selection.
  final bool enabled;
}

class MenuItems {
  static const List<MenuItem> items = [
    MenuItem(index: 0, title: 'COMMAND CENTER', icon: Icons.dashboard_outlined),
    MenuItem(index: 1, title: 'MUSIC EMPIRE', icon: Icons.library_music_outlined),
    MenuItem(index: 2, title: 'WAR ROOM', icon: Icons.sports_mma_outlined),
    MenuItem(index: 3, title: 'THE NATION', icon: Icons.people_outline),
    MenuItem(index: 4, title: 'THRONE ROOM', icon: Icons.person_outline),
  ];
}
