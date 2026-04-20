String canonicalPlanId(String value) {
  final normalized = normalizePlanKey(value);
  switch (normalized) {
    case 'vip':
    case 'vip_listener':
      return 'platinum';
    default:
      return normalized;
  }
}

bool isFreeLikePlanId(String value) {
  final id = canonicalPlanId(value);
  return id == 'free' ||
      id == 'starter' ||
      id == 'artist_starter' ||
      id == 'dj_starter' ||
      id == 'artist_free' ||
      id == 'dj_free' ||
      id.startsWith('free_') ||
      id.startsWith('starter_') ||
      id.startsWith('artist_starter_') ||
      id.startsWith('dj_starter_') ||
      id.startsWith('artist_free_') ||
      id.startsWith('dj_free_');
}

bool isCreatorPlanId(String value) {
  final id = canonicalPlanId(value);
  return id == 'artist_starter' ||
      id == 'artist_pro' ||
      id == 'artist_premium' ||
      id == 'artist_free' ||
      id == 'dj_starter' ||
      id == 'dj_pro' ||
      id == 'dj_premium' ||
      id == 'dj_free' ||
      id.startsWith('artist_') ||
      id.startsWith('dj_');
}

bool isLegacyCompatibilityPlanId(String value) {
  final id = canonicalPlanId(value);
  if (id.isEmpty) return false;

  return id == 'family' ||
      id == 'starter' ||
      id == 'pro' ||
      id == 'elite' ||
      id == 'premium_weekly' ||
      id == 'platinum_weekly' ||
      id == 'pro_weekly' ||
      id == 'elite_weekly' ||
      id.endsWith('_weekly');
}

String displayNameForPlanId(String value) {
  switch (canonicalPlanId(value)) {
    case 'free':
      return 'Free';
    case 'premium':
      return 'Premium';
    case 'platinum':
      return 'Platinum';
    case 'artist_starter':
      return 'Artist Free';
    case 'artist_pro':
      return 'Artist Pro';
    case 'artist_premium':
      return 'Artist Premium';
    case 'dj_starter':
      return 'DJ Free';
    case 'dj_pro':
      return 'DJ Pro';
    case 'dj_premium':
      return 'DJ Premium';
  }

  final id = canonicalPlanId(value);
  if (id.isEmpty) return '';
  return id
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String? defaultAudienceForPlanId(String value) {
  final id = canonicalPlanId(value);
  if (id.isEmpty) return null;
  if (id.startsWith('artist_')) return 'artist';
  if (id.startsWith('dj_')) return 'dj';
  if (id == 'free' || id == 'premium' || id == 'platinum') return 'consumer';
  return null;
}

bool defaultTrialEligibleForPlanId(String value) {
  final id = canonicalPlanId(value);
  return id == 'artist_starter' || id == 'dj_starter';
}

int defaultTrialDurationDaysForPlanId(String value) {
  return defaultTrialEligibleForPlanId(value) ? 7 : 0;
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.planId,
    required this.name,
    required this.priceMwk,
    required this.billingInterval,
    this.backendId,
    this.currency = 'MWK',
    this.audience,
    this.features = const <String, dynamic>{},
    this.perks = const <String, dynamic>{},
    this.trialEligible = false,
    this.trialDurationDays = 0,
    this.marketingBullets = const <String>[],
    this.marketingTagline,
  });

  final String planId;
  final String name;
  final int priceMwk;
  final String billingInterval;

  /// Optional backend primary key (some APIs return both `id` and `plan_id`).
  final String? backendId;

  final String currency;

  final String? audience;

  /// Backend-driven feature flags / entitlements for UI gating.
  final Map<String, dynamic> features;

  /// Lightweight plan presentation and gating payload returned separately
  /// from `features` by the canonical backend contract.
  final Map<String, dynamic> perks;

  final bool trialEligible;

  final int trialDurationDays;

  /// Backend-driven marketing bullets for plan display.
  ///
  /// Keep copy out of the app when possible; prefer returning this from the API.
  final List<String> marketingBullets;

  /// Optional short marketing one-liner.
  final String? marketingTagline;

  bool get hasTrialOffer => trialEligible && trialDurationDays > 0;

  bool get isFree {
    final label = name.toLowerCase();
    return isFreeLikePlanId(planId) ||
        (planId.trim().isEmpty &&
            (label == 'free' || label.startsWith('free ')));
  }

  static SubscriptionPlan fromJson(Map<String, dynamic> json) {
    final rawPlanId =
        (json['plan_id'] ??
                json['planId'] ??
                json['code'] ??
                json['slug'] ??
                json['plan'] ??
                '')
            .toString()
            .trim();
    final planId = canonicalPlanId(rawPlanId);
    final rawId = (json['id'] ?? '').toString().trim();
    final backendId = rawId.isEmpty || canonicalPlanId(rawId) == planId
        ? null
        : rawId;
    final name = (json['name'] ?? planId).toString().trim();

    final rawPrice = json['price_mwk'] ?? json['price'] ?? 0;
    final priceMwk = rawPrice is num
        ? rawPrice.round()
        : int.tryParse(rawPrice.toString()) ?? 0;

    final billingInterval = (json['billing_interval'] ?? json['interval'] ?? '')
        .toString()
        .trim();

    final currency = (json['currency'] ?? json['currency_code'] ?? 'MWK')
        .toString()
        .trim();
    final audience = (json['audience'] ?? defaultAudienceForPlanId(planId))
      ?.toString()
      .trim();

    Map<String, dynamic> features = const <String, dynamic>{};
    final rawFeatures =
        json['features'] ?? json['entitlements'] ?? json['flags'];
    if (rawFeatures is Map) {
      features = rawFeatures.map((k, v) => MapEntry(k.toString(), v));
    }

    Map<String, dynamic> perks = const <String, dynamic>{};
    final rawPerks = json['perks'];
    if (rawPerks is Map) {
      perks = rawPerks.map((k, v) => MapEntry(k.toString(), v));
    }

    final defaultTrialEligible = defaultTrialEligibleForPlanId(planId);
    final trialEligible =
      _boolFromDynamic(json['trial_eligible'] ?? json['trialEligible']) ??
      defaultTrialEligible;
    final trialDurationDays =
      _intFromDynamic(
        json['trial_duration_days'] ?? json['trialDurationDays'],
      ) ??
      (trialEligible ? defaultTrialDurationDaysForPlanId(planId) : 0);

    String? marketingTagline;
    List<String> marketingBullets = const <String>[];
    final rawMarketing = json['marketing'];
    if (rawMarketing is Map) {
      final m = rawMarketing.map((k, v) => MapEntry(k.toString(), v));
      marketingTagline = (m['tagline'] ?? m['subtitle'])?.toString().trim();
      marketingBullets = _stringListFrom(
        m['bullets'] ?? m['features'] ?? m['items'],
      );
    } else {
      marketingBullets = _stringListFrom(
        json['marketing_bullets'] ?? json['bullets'],
      );
      final tag =
          json['marketing_tagline'] ?? json['tagline'] ?? json['subtitle'];
      marketingTagline = tag?.toString().trim();
    }

    return SubscriptionPlan(
      planId: planId.isNotEmpty ? planId : rawId,
      name: name,
      priceMwk: priceMwk,
      billingInterval: billingInterval,
      backendId: backendId,
      currency: currency.isEmpty ? 'MWK' : currency,
      audience: audience == null || audience.isEmpty ? null : audience,
      features: features,
      perks: perks,
      trialEligible: trialEligible,
      trialDurationDays: trialDurationDays < 0 ? 0 : trialDurationDays,
      marketingBullets: marketingBullets,
      marketingTagline: marketingTagline,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'plan_id': planId,
      if (backendId != null) 'id': backendId,
      'name': name,
      'price_mwk': priceMwk,
      'billing_interval': billingInterval,
      'currency': currency,
      if (audience != null) 'audience': audience,
      'features': features,
      'perks': perks,
      'trial_eligible': trialEligible,
      'trial_duration_days': trialDurationDays,
      if (marketingBullets.isNotEmpty) 'marketing_bullets': marketingBullets,
      if (marketingTagline != null) 'marketing_tagline': marketingTagline,
    };
  }
}

/// Normalizes plan identifiers so the UI can match plans to `/me` values even
/// when backends use slightly different IDs.
///
/// Primary use-case: ignore billing interval suffixes (e.g. `premium_monthly` vs `premium`).
///
/// Important: do NOT collapse multi-token IDs to the first token, because that
/// breaks creator tiers like `artist_premium` vs `artist_pro`.
String normalizePlanKey(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return '';

  const intervalTokens = <String>{
    'day',
    'daily',
    'week',
    'weekly',
    'wk',
    'month',
    'monthly',
    'mo',
    'year',
    'yearly',
    'yr',
    'annual',
    'annually',
    'days',
    'weeks',
    'months',
    'years',
  };

  final parts = v
      .split(RegExp(r'[_\-\s]+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return v;

  final filtered = parts
      .where((p) => !intervalTokens.contains(p))
      .toList(growable: false);
  final out = filtered.isEmpty ? parts : filtered;
  return out.join('_');
}

bool planIdMatches(String a, String b) {
  if (a.trim().isEmpty || b.trim().isEmpty) return false;
  if (canonicalPlanId(a) == canonicalPlanId(b)) return true;
  final na = canonicalPlanId(a);
  final nb = canonicalPlanId(b);
  if (na.isEmpty || nb.isEmpty) return false;
  return na == nb;
}

List<String> _stringListFrom(dynamic value) {
  if (value == null) return const <String>[];
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return const <String>[];
    return <String>[s];
  }
  return const <String>[];
}

bool? _boolFromDynamic(dynamic value) {
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

int? _intFromDynamic(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
