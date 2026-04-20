import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../features/subscriptions/models/subscription_capabilities.dart';
import '../features/subscriptions/subscriptions_controller.dart';
import 'content_access_policy.dart';

enum ContentAccessGateEventType {
  blocked,
}

class ContentAccessGateEvent {
  const ContentAccessGateEvent({
    required this.type,
    required this.capability,
    required this.contentId,
    required this.reason,
  });

  final ContentAccessGateEventType type;
  final ConsumerCapability capability;
  final String contentId;
  final ContentAccessBlockReason reason;
}

class ContentAccessGate {
  ContentAccessGate({SubscriptionsController? subscriptions})
      : _subscriptions = subscriptions ?? SubscriptionsController.instance;

  static final ContentAccessGate instance = ContentAccessGate();

  final SubscriptionsController _subscriptions;

  final _controller = StreamController<ContentAccessGateEvent>.broadcast();

  Stream<ContentAccessGateEvent> get events => _controller.stream;

  ContentAccessDecision check({
    required String contentId,
    required bool isExclusive,
  }) {
    return ContentAccessPolicy.decide(
      entitlements: _subscriptions.entitlements,
      contentId: contentId,
      isExclusive: isExclusive,
      userKey: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  bool ensureNotifiedBlocked({
    required String contentId,
    required bool isExclusive,
  }) {
    final decision = check(contentId: contentId, isExclusive: isExclusive);
    if (decision.allowed) return true;

    final reason = decision.reason;
    if (reason == null) return false;

    final capability = switch (reason) {
      ContentAccessBlockReason.exclusive => ConsumerCapability.exclusiveContent,
      ContentAccessBlockReason.ratio => ConsumerCapability.contentAccess,
    };

    // Best-effort: do not await; UI listens in AppShell.
    _controller.add(
      ContentAccessGateEvent(
        type: ContentAccessGateEventType.blocked,
        capability: capability,
        contentId: contentId,
        reason: reason,
      ),
    );
    return false;
  }
}
