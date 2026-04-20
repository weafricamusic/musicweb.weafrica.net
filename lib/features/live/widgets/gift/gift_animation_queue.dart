import 'dart:async';
import 'dart:collection';

import '../../models/gift_model.dart';

class GiftAnimationQueue {
  GiftAnimationQueue({
    required void Function(GiftModel gift) onShow,
    required void Function(GiftModel gift) onHide,
    this.defaultDisplayDuration = const Duration(milliseconds: 2200),
  })  : _onShow = onShow,
        _onHide = onHide;

  final void Function(GiftModel gift) _onShow;
  final void Function(GiftModel gift) _onHide;
  final Duration defaultDisplayDuration;

  final Queue<_QueuedGift> _pending = Queue<_QueuedGift>();

  Timer? _timer;
  _QueuedGift? _currentGift;

  bool get isPlaying => _currentGift != null;

  /// Enqueue a gift with optional custom duration
  void enqueue(GiftModel gift, {Duration? customDuration}) {
    _pending.addLast(_QueuedGift(gift, customDuration ?? defaultDisplayDuration));
    _pump();
  }

  /// Clears all pending gifts and hides the current one
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();

    final current = _currentGift;
    _currentGift = null;
    if (current != null) {
      _onHide(current.gift);
    }
  }

  void dispose() {
    clear();
  }

  void _pump() {
    if (_currentGift != null || _pending.isEmpty) return;

    final next = _pending.removeFirst();
    _currentGift = next;
    _onShow(next.gift);

    _timer?.cancel();
    _timer = Timer(next.displayDuration, () {
      final shown = _currentGift;
      _currentGift = null;
      if (shown != null) {
        _onHide(shown.gift);
      }
      _pump();
    });
  }
}

/// Internal wrapper to store gift + custom duration
class _QueuedGift {
  _QueuedGift(this.gift, this.displayDuration);

  final GiftModel gift;
  final Duration displayDuration;
}