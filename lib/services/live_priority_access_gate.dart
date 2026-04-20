import 'dart:async';

import '../features/subscriptions/models/subscription_capabilities.dart';
import '../features/subscriptions/subscriptions_controller.dart';

enum LivePriorityAccessGateEventType {
  blocked,
  unblocked,
}

class LivePriorityAccessGateEvent {
  const LivePriorityAccessGateEvent({
    required this.type,
    required this.capability,
    required this.channelId,
    required this.accessTier,
  });

  final LivePriorityAccessGateEventType type;
  final ConsumerCapability capability;
  final String channelId;
  final String accessTier;
}

class LivePriorityAccessGate {
  LivePriorityAccessGate({SubscriptionsController? subscriptions})
      : _subscriptions = subscriptions ?? SubscriptionsController.instance;

  static final LivePriorityAccessGate instance = LivePriorityAccessGate();

  final SubscriptionsController _subscriptions;

  final _controller = StreamController<LivePriorityAccessGateEvent>.broadcast();

  final Map<String, DateTime> _lastBlockedAtByChannel = <String, DateTime>{};

  static const Duration _blockedRetryWindow = Duration(minutes: 2);

  Stream<LivePriorityAccessGateEvent> get events => _controller.stream;

  bool wasBlockedRecently(String channelId, {Duration within = _blockedRetryWindow}) {
    final ch = channelId.trim();
    if (ch.isEmpty) return false;
    final at = _lastBlockedAtByChannel[ch];
    if (at == null) return false;
    return DateTime.now().difference(at) <= within;
  }

  /// Used by UI to await an upgrade completion signal before retrying.
  Future<bool> waitForUnblocked(
    String channelId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final ch = channelId.trim();
    if (ch.isEmpty) return false;

    final completer = Completer<bool>();
    late final StreamSubscription<LivePriorityAccessGateEvent> sub;
    sub = events.listen((event) {
      if (event.type != LivePriorityAccessGateEventType.unblocked) return;
      if (event.channelId.trim() != ch) return;
      if (!completer.isCompleted) completer.complete(true);
      unawaited(sub.cancel());
    });

    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      unawaited(sub.cancel());
    }
  }

  void notifyUpgraded({required String channelId, required String accessTier}) {
    final ch = channelId.trim();
    if (ch.isEmpty) return;

    _controller.add(
      LivePriorityAccessGateEvent(
        type: LivePriorityAccessGateEventType.unblocked,
        capability: ConsumerCapability.priorityLiveAccess,
        channelId: ch,
        accessTier: accessTier.trim().toLowerCase(),
      ),
    );
  }

  bool ensureAllowed({
    required String channelId,
    required String accessTier,
    required bool asBroadcaster,
  }) {
    final tier = accessTier.trim().toLowerCase();
    if (tier.isEmpty || tier == 'standard') return true;

    // Broadcasters/hosts must be able to join their own sessions.
    if (asBroadcaster) return true;

    if (tier == 'priority' && !_subscriptions.entitlements.effectivePriorityLiveAccessEnabled) {
      _lastBlockedAtByChannel[channelId.trim()] = DateTime.now();
      _controller.add(
        LivePriorityAccessGateEvent(
          type: LivePriorityAccessGateEventType.blocked,
          capability: ConsumerCapability.priorityLiveAccess,
          channelId: channelId,
          accessTier: tier,
        ),
      );
      return false;
    }

    return true;
  }
}
