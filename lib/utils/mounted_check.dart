import 'package:flutter/material.dart';

/// Extension to safely call setState only if the widget is still mounted
extension SafeSetState on State {
  /// Call setState only if the widget is still mounted
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}
