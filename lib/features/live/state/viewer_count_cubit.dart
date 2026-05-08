import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tracks the viewer count in real-time.
class ViewerCountCubit extends ValueNotifier<int> {
  StreamSubscription? _sub;

  ViewerCountCubit() : super(0);

  void startWatching(Stream<int> countStream) {
    _sub?.cancel();
    _sub = countStream.listen((count) {
      value = count;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
