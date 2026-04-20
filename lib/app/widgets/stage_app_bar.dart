import 'package:flutter/material.dart';

import '../theme/weafrica_colors.dart';

class StageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StageAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: leading,
      title: Text(
        title,
        style: const TextStyle(
          color: WeAfricaColors.gold,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      actions: actions,
      iconTheme: const IconThemeData(color: WeAfricaColors.gold),
    );
  }
}
