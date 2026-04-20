import '../features/subscriptions/models/subscription_me.dart';

enum ContentAccessBlockReason {
  exclusive,
  ratio,
}

class ContentAccessDecision {
  const ContentAccessDecision._({
    required this.allowed,
    required this.reason,
  });

  final bool allowed;
  final ContentAccessBlockReason? reason;

  const ContentAccessDecision.allowed() : this._(allowed: true, reason: null);

  const ContentAccessDecision.blocked(ContentAccessBlockReason reason)
      : this._(allowed: false, reason: reason);
}

class ContentAccessPolicy {
  const ContentAccessPolicy._();

  static ContentAccessDecision decide({
    required Entitlements entitlements,
    required String contentId,
    required bool isExclusive,
    String? userKey,
  }) {
    final id = contentId.trim();
    if (id.isEmpty) return const ContentAccessDecision.allowed();

    if (isExclusive && !entitlements.effectiveExclusiveContentEnabled) {
      return const ContentAccessDecision.blocked(ContentAccessBlockReason.exclusive);
    }

    final access = entitlements.effectiveContentAccess.trim().toLowerCase();
    if (access != 'limited') {
      return const ContentAccessDecision.allowed();
    }

    final ratio = entitlements.effectiveContentLimitRatio;
    if (ratio >= 1.0) return const ContentAccessDecision.allowed();
    if (ratio <= 0.0) return const ContentAccessDecision.blocked(ContentAccessBlockReason.ratio);

    final bucket = _bucket01(contentId: id, userKey: userKey);
    if (bucket < ratio) return const ContentAccessDecision.allowed();
    return const ContentAccessDecision.blocked(ContentAccessBlockReason.ratio);
  }

  /// Stable 0..1 bucket.
  ///
  /// If [userKey] is provided, the allowed subset is randomized per user,
  /// avoiding a global “same tracks blocked for everyone” experience.
  static double _bucket01({required String contentId, String? userKey}) {
    final salt = (userKey ?? '').trim();
    final seed = salt.isEmpty ? contentId : '$salt|$contentId';
    final hash = _fnv1a32(seed);
    // Use 10k buckets for stable, smooth ratios.
    final bucket = hash % 10000;
    return bucket / 10000.0;
  }

  static int _fnv1a32(String input) {
    const int fnvOffset = 0x811c9dc5;
    const int fnvPrime = 0x01000193;

    var hash = fnvOffset;
    for (final unit in input.codeUnits) {
      hash ^= unit & 0xff;
      hash = (hash * fnvPrime) & 0xffffffff;
    }
    return hash;
  }
}
