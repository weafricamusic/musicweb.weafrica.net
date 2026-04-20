import 'package:flutter/material.dart';

import '../theme/weafrica_colors.dart';

class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ModernAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.bottom,
  });

  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [WeAfricaColors.gold, WeAfricaColors.goldLight],
        ).createShader(bounds),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
      leading: showBack
          ? Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: WeAfricaColors.goldWithOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: WeAfricaColors.goldWithOpacity(0.3)),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: WeAfricaColors.gold),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      actions: actions,
      bottom: bottom is PreferredSizeWidget ? bottom as PreferredSizeWidget : null,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
        56.0 + (bottom is PreferredSizeWidget ? (bottom as PreferredSizeWidget).preferredSize.height : 0),
      );
}
