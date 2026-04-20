import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/subscription_plan.dart';

class SubscriptionPlansCache {
  SubscriptionPlansCache({Duration? maxAge})
      : _maxAge = maxAge ?? const Duration(hours: 12);

  static const String _boxName = 'subscriptions.plans.cache.v1';

  final Duration _maxAge;

  Future<Box<dynamic>>? _boxFuture;

  Future<Box<dynamic>> _box() {
    final existing = _boxFuture;
    if (existing != null) return existing;
    final created = Hive.openBox<dynamic>(_boxName);
    _boxFuture = created;
    return created;
  }

  String _keyFor(String audience) {
    final a = audience.trim().toLowerCase();
    return 'audience:${a.isEmpty ? 'consumer' : a}';
  }

  Future<List<SubscriptionPlan>?> readFresh({required String audience}) async {
    try {
      final box = await _box();
      final raw = box.get(_keyFor(audience));
      if (raw is! String) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final savedAtRaw = decoded['savedAt']?.toString();
      final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
      if (savedAt == null) return null;

      if (DateTime.now().difference(savedAt) > _maxAge) return null;

      final items = decoded['items'];
      if (items is! List) return null;

      return items
          .whereType<Map>()
          .map((m) => SubscriptionPlan.fromJson(
                Map<String, dynamic>.from(m.cast()),
              ))
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionPlansCache.readFresh failed: $e');
      }
      return null;
    }
  }

  Future<List<SubscriptionPlan>?> readStaleOk({required String audience}) async {
    try {
      final box = await _box();
      final raw = box.get(_keyFor(audience));
      if (raw is! String) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final items = decoded['items'];
      if (items is! List) return null;

      return items
          .whereType<Map>()
          .map((m) => SubscriptionPlan.fromJson(
                Map<String, dynamic>.from(m.cast()),
              ))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required String audience, required List<SubscriptionPlan> plans}) async {
    try {
      final box = await _box();
      final payload = <String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'audience': audience.trim().toLowerCase(),
        'items': plans.map((p) => p.toJson()).toList(growable: false),
      };
      await box.put(_keyFor(audience), jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionPlansCache.write failed: $e');
      }
    }
  }
}
