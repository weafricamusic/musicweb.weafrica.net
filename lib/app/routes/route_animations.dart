import 'package:flutter/material.dart';

/// Lightweight route helper.
///
/// Keep this minimal so it doesn't conflict with existing navigation patterns.
class RouteAnimations {
  static PageRoute<T> fade<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}
