import 'package:flutter/material.dart';

/// Global navigation entry point for services (FCM, deep links, etc.)
/// that need to navigate without having a BuildContext.
class AppNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static BuildContext? get context => key.currentContext;

  static Future<T?> push<T>(Route<T> route) {
    final state = key.currentState;
    if (state == null) return Future<T?>.value(null);
    return state.push(route);
  }

  static void popUntilRoot() {
    key.currentState?.popUntil((r) => r.isFirst);
  }
}
