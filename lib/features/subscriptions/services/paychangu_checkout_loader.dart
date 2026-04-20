import 'dart:async';

import '../models/subscription_plan.dart';
import 'subscriptions_api.dart';

class PayChanguCheckoutLoader {
  PayChanguCheckoutLoader();

  static final PayChanguCheckoutLoader instance = PayChanguCheckoutLoader();

  static const Duration defaultTtl = Duration(minutes: 5);

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  Future<Uri> preload({
    required SubscriptionPlan plan,
    Duration ttl = defaultTtl,
  }) async {
    final session = await _getOrCreateSession(plan: plan, ttl: ttl);
    return session.checkoutUrl;
  }

  Future<PayChanguCheckoutSession> preloadSession({
    required SubscriptionPlan plan,
    Duration ttl = defaultTtl,
  }) {
    return _getOrCreateSession(plan: plan, ttl: ttl);
  }

  Future<Uri> getOrCreate({
    required SubscriptionPlan plan,
    Duration ttl = defaultTtl,
  }) async {
    final session = await _getOrCreateSession(plan: plan, ttl: ttl);
    return session.checkoutUrl;
  }

  Future<PayChanguCheckoutSession> getOrCreateSession({
    required SubscriptionPlan plan,
    Duration ttl = defaultTtl,
  }) {
    return _getOrCreateSession(plan: plan, ttl: ttl);
  }

  void invalidatePlanId(String planId) {
    _cache.remove(planId.trim().toLowerCase());
  }

  void invalidateAll() {
    _cache.clear();
  }

  Future<PayChanguCheckoutSession> _getOrCreateSession({
    required SubscriptionPlan plan,
    required Duration ttl,
  }) async {
    final key = plan.planId.trim().toLowerCase();
    final existing = _cache[key];

    if (existing != null) {
      if (existing.session != null && !existing.isExpired(ttl)) {
        return existing.session!;
      }

      final inflight = existing.inFlight;
      if (inflight != null) {
        return inflight;
      }
    }

    final entry = existing ?? _CacheEntry();
    final future = SubscriptionsApi.startPayChanguPaymentSession(plan: plan).then((session) {
      entry
        ..session = session
        ..createdAt = DateTime.now()
        ..inFlight = null;
      return session;
    }).catchError((e) {
      entry.inFlight = null;
      throw e;
    });

    entry.inFlight = future;
    _cache[key] = entry;

    return future;
  }
}

class _CacheEntry {
  PayChanguCheckoutSession? session;
  DateTime? createdAt;
  Future<PayChanguCheckoutSession>? inFlight;

  bool isExpired(Duration ttl) {
    final at = createdAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > ttl;
  }
}
