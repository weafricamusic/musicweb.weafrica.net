import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tracks the current Navigator route stack.
///
/// This enables services (FCM, deep links) to avoid pushing duplicate screens
/// (e.g. stacking multiple full-player routes on notification floods).
class AppRouteTracker extends NavigatorObserver {
  AppRouteTracker._();

  static final AppRouteTracker instance = AppRouteTracker._();

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// Emit the top-most route whenever navigation changes.
  final ValueNotifier<Route<dynamic>?> currentRoute = ValueNotifier<Route<dynamic>?>(null);

  String? get currentName => currentRoute.value?.settings.name;

  bool containsName(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    return _stack.any((r) => r.settings.name == n);
  }

  Route<dynamic>? lastRouteNamed(String name) {
    final n = name.trim();
    if (n.isEmpty) return null;
    for (var i = _stack.length - 1; i >= 0; i--) {
      final r = _stack[i];
      if (r.settings.name == n) return r;
    }
    return null;
  }

  void _setCurrent(Route<dynamic>? route) {
    if (currentRoute.value == route) return;
    currentRoute.value = route;

    if (kDebugMode) {
      final n = route?.settings.name;
      if (n != null && n.trim().isNotEmpty) {
        debugPrint('🧭 route: $n');
      }
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route);
    _setCurrent(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _stack.remove(route);
    _setCurrent(previousRoute ?? (_stack.isNotEmpty ? _stack.last : null));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _stack.remove(route);
    _setCurrent(previousRoute ?? (_stack.isNotEmpty ? _stack.last : null));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) {
      _stack.remove(oldRoute);
    }
    if (newRoute != null) {
      _stack.add(newRoute);
      _setCurrent(newRoute);
    } else {
      _setCurrent(_stack.isNotEmpty ? _stack.last : null);
    }
  }
}
