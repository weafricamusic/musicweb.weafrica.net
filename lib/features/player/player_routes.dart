import 'package:flutter/material.dart';

import '../../screens/full_player_screen.dart';

void openPlayer(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      settings: const RouteSettings(name: '/player/full'),
      pageBuilder: (context, animation, secondaryAnimation) => const FullPlayerScreen(),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        return SlideTransition(
          position: animation.drive(slide),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    ),
  );
}
