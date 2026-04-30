import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gift_model.dart';
import '../widgets/gift/gift_animation_queue.dart';

/// Controller to manage gifts during a live stream or battle.
class GiftController extends ChangeNotifier {
  GiftController() {
    // Initialize the gift animation queue
    _queue = GiftAnimationQueue(
      onShow: _showGift,
      onHide: _hideGift,
    );
  }

  // Currently displayed gifts
  final List<GiftModel> _activeGifts = <GiftModel>[];

  // Combo counter (number of gifts sent consecutively)
  int _comboCount = 0;

  // Timer to reset combo count after a short delay
  Timer? _comboResetTimer;

  // Queue to manage sequential gift animations
  late final GiftAnimationQueue _queue;

  /// Read-only list of active gifts
  List<GiftModel> get activeGifts => List<GiftModel>.unmodifiable(_activeGifts);

  /// Current combo count
  int get comboCount => _comboCount;

  /// Send a gift (local user action)
  void sendGift(GiftModel gift) => _enqueueGift(gift);

  /// Receive a gift (from another user)
  void receiveGift(GiftModel gift) => _enqueueGift(gift);

  /// Manually show a gift (used by some overlays/tests that manage their own queue).
  void addGift(GiftModel gift) => _showGift(gift);

  /// Manually hide a gift (used by some overlays/tests that manage their own queue).
  void removeGift(GiftModel gift) => _hideGift(gift);

  /// Enqueue gift to animation queue and increase combo
  void _enqueueGift(GiftModel gift) {
    _queue.enqueue(gift); // Add to animation queue

    _comboCount += 1;
    notifyListeners();

    // Reset combo count after 3 seconds of inactivity
    _comboResetTimer?.cancel();
    _comboResetTimer = Timer(const Duration(seconds: 3), () {
      _comboCount = 0;
      notifyListeners();
    });
  }

  /// Called by queue when a gift should appear on screen
  void _showGift(GiftModel gift) {
    if (_activeGifts.contains(gift)) {
      notifyListeners();
      return;
    }

    _activeGifts.add(gift);
    notifyListeners();
  }

  /// Called by queue when a gift animation ends
  void _hideGift(GiftModel gift) {
    final idx = _activeGifts.indexWhere((g) => identical(g, gift));
    if (idx < 0) return;

    _activeGifts.removeAt(idx);
    notifyListeners();
  }

  @override
  void dispose() {
    _comboResetTimer?.cancel();
    _queue.dispose();
    super.dispose();
  }
}