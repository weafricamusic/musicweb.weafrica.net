import 'gifting_tier.dart';
import 'subscription_plan.dart';

bool? _boolLike(dynamic value) {
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

int? _nonNegativeInt(dynamic value) {
  if (value is int) return value < 0 ? 0 : value;
  if (value is num) {
    final rounded = value.round();
    return rounded < 0 ? 0 : rounded;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return null;
    return parsed < 0 ? 0 : parsed;
  }
  return null;
}

DateTime? _dateTimeLike(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) return value;

  if (value is int) {
    if (value <= 0) return null;

    // Heuristic: seconds vs milliseconds.
    if (value > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }

    return null;
  }

  if (value is num) {
    return _dateTimeLike(value.toInt());
  }

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }

  return null;
}

String? _planAudience(dynamic rawAudience, String planId) {
  final normalized = rawAudience?.toString().trim().toLowerCase() ?? '';
  if (normalized == 'consumer' || normalized == 'artist' || normalized == 'dj') {
    return normalized;
  }
  return defaultAudienceForPlanId(planId);
}

class SubscriptionMe {
  const SubscriptionMe({
    required this.planId,
    required this.status,
    required this.entitlements,
    required this.raw,
    this.audience,
    this.trialEligible = false,
    this.trialDurationDays = 0,
    this.currentPeriodEnd,
    this.gracePeriodEnd,
  });

  final String planId;
  final String status;
  final Entitlements entitlements;

  /// Preserve original payload for forward compatibility.
  final Map<String, dynamic> raw;

  final String? audience;

  final bool trialEligible;

  final int trialDurationDays;

  /// End of the current billing / trial period.
  ///
  /// When present, this enables trial countdown UX (“X days left”) and renewal
  /// messaging.
  final DateTime? currentPeriodEnd;

  /// End of the grace period when a payment fails.
  ///
  /// Optional; depends on backend support.
  final DateTime? gracePeriodEnd;

  bool get isActive =>
      status.toLowerCase() == 'active' || status.toLowerCase() == 'trialing';

  bool get hasTrialOffer => trialEligible && trialDurationDays > 0;

  static SubscriptionMe fromJson(Map<String, dynamic> json) {
    // Support multiple backend shapes:
    // - { plan_id, status, entitlements }
    // - { subscription: { plan_id, status, entitlements }, entitlements? }
    // - { subscription: null, plan: { plan_id, ... }, entitlements }
    // - { subscription: null } => treat as Free
    final sub = json['subscription'];
    final Map<String, dynamic> subObj = sub is Map
        ? sub.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final subPlan = subObj['plan'];
    final Map<String, dynamic> subPlanObj = subPlan is Map
        ? subPlan.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final String? subPlanToken = subPlan is String ? subPlan : null;

    final plan = json['plan'];
    final Map<String, dynamic> planObj = plan is Map
        ? plan.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final String? planToken = plan is String ? plan : null;

    final bool subscriptionIsNull =
        json.containsKey('subscription') && sub == null;

    final rawEnt = json['entitlements'] ?? subObj['entitlements'];
    final Map<String, dynamic> entObj = rawEnt is Map
        ? rawEnt.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};

    final rawPlanId =
        (subscriptionIsNull
                ? (planObj['plan_id'] ??
                      planObj['planId'] ??
                      planToken ??
                      entObj['plan_id'] ??
                      entObj['planId'] ??
                      json['plan_id'] ??
                      json['planId'] ??
                      json['current_plan_id'] ??
                      json['currentPlanId'] ??
                      'free')
                : (subObj['plan_id'] ??
                      subObj['planId'] ??
                      subPlanObj['plan_id'] ??
                      subPlanObj['planId'] ??
                      subPlanToken ??
                      planObj['plan_id'] ??
                      planObj['planId'] ??
                      planToken ??
                      entObj['plan_id'] ??
                      entObj['planId'] ??
                      json['plan_id'] ??
                      json['planId'] ??
                      json['current_plan_id'] ??
                      json['currentPlanId'] ??
                      'free'))
            .toString()
            .trim();
    final planId = canonicalPlanId(rawPlanId).isEmpty
        ? 'free'
        : canonicalPlanId(rawPlanId);

    final audience = _planAudience(
      subscriptionIsNull
        ? (planObj['audience'] ?? json['audience'])
        : (subObj['audience'] ??
          subPlanObj['audience'] ??
          planObj['audience'] ??
          json['audience']),
      planId,
    );

    final defaultTrialEligible = defaultTrialEligibleForPlanId(planId);
    final trialEligible =
      _boolLike(
        subscriptionIsNull
          ? (planObj['trial_eligible'] ??
            planObj['trialEligible'] ??
            json['trial_eligible'] ??
            json['trialEligible'])
          : (subObj['trial_eligible'] ??
            subObj['trialEligible'] ??
            subPlanObj['trial_eligible'] ??
            subPlanObj['trialEligible'] ??
            planObj['trial_eligible'] ??
            planObj['trialEligible'] ??
            json['trial_eligible'] ??
            json['trialEligible']),
      ) ??
      defaultTrialEligible;
    final trialDurationDays =
      _nonNegativeInt(
        subscriptionIsNull
          ? (planObj['trial_duration_days'] ??
            planObj['trialDurationDays'] ??
            json['trial_duration_days'] ??
            json['trialDurationDays'])
          : (subObj['trial_duration_days'] ??
            subObj['trialDurationDays'] ??
            subPlanObj['trial_duration_days'] ??
            subPlanObj['trialDurationDays'] ??
            planObj['trial_duration_days'] ??
            planObj['trialDurationDays'] ??
            json['trial_duration_days'] ??
            json['trialDurationDays']),
      ) ??
      (trialEligible ? defaultTrialDurationDaysForPlanId(planId) : 0);

      final rawCurrentPeriodEnd = subscriptionIsNull
        ? (planObj['current_period_end'] ??
          planObj['currentPeriodEnd'] ??
          json['current_period_end'] ??
          json['currentPeriodEnd'])
        : (subObj['current_period_end'] ??
          subObj['currentPeriodEnd'] ??
          json['current_period_end'] ??
          json['currentPeriodEnd']);
      final currentPeriodEnd = _dateTimeLike(rawCurrentPeriodEnd);

      final rawGracePeriodEnd = subscriptionIsNull
        ? (planObj['grace_period_end'] ??
          planObj['gracePeriodEnd'] ??
          json['grace_period_end'] ??
          json['gracePeriodEnd'])
        : (subObj['grace_period_end'] ??
          subObj['gracePeriodEnd'] ??
          json['grace_period_end'] ??
          json['gracePeriodEnd']);
      final gracePeriodEnd = _dateTimeLike(rawGracePeriodEnd);

    final status =
        (subscriptionIsNull
                ? (planObj['status'] ??
                      planObj['state'] ??
                      json['status'] ??
                      json['state'] ??
                      json['subscription_status'] ??
                      (json['active'] == true ? 'active' : 'inactive'))
                : (subObj['status'] ??
                      subObj['state'] ??
                      subPlanObj['status'] ??
                      subPlanObj['state'] ??
                      planObj['status'] ??
                      planObj['state'] ??
                      json['status'] ??
                      json['state'] ??
                      json['subscription_status'] ??
                      (json['active'] == true ? 'active' : 'inactive')))
            .toString()
            .trim();

    final entitlements = rawEnt is Map<String, dynamic>
        ? Entitlements.fromJson(rawEnt)
        : rawEnt is Map
        ? Entitlements.fromJson(rawEnt.map((k, v) => MapEntry(k.toString(), v)))
        : const Entitlements();

    return SubscriptionMe(
      planId: planId,
      status: status,
      entitlements: entitlements,
      raw: json,
      audience: audience,
      trialEligible: trialEligible,
      trialDurationDays: trialDurationDays,
      currentPeriodEnd: currentPeriodEnd,
      gracePeriodEnd: gracePeriodEnd,
    );
  }
}

enum _CreatorTier {
  starter,
  pro,
  premium,
}

class Entitlements {
  const Entitlements({
    this.raw = const <String, dynamic>{},
    this.adsEnabled,
    this.interstitialEverySongs,
    this.backgroundPlayEnabled,
    this.downloadsEnabled,
    this.videoDownloadsEnabled,
    this.playlistsCreateEnabled,
    this.playlistsMixEnabled,
    this.maxAudioKbps,
    this.maxSkipsPerHour,
    this.giftingTier,
    this.vipBadgeEnabled,
    this.highlightedCommentsEnabled,
    this.exclusiveContentEnabled,
    this.priorityLiveAccessEnabled,
    this.songRequestsEnabled,
    this.earlyAccessEnabled,
    this.contentAccess,
    this.contentLimitRatio,
    this.battlePriority,
    this.featured,
    this.monthlyFreeCoins,
    this.weeklyFreeCoins,
    this.monthlyBonusCoins,
  });

  /// Full entitlements payload for forward-compatible feature gating.
  final Map<String, dynamic> raw;

  /// Whether ads should run at all.
  ///
  /// Your backend may return `entitlements.ads_enabled` or derive it.
  final bool? adsEnabled;

  /// For Free plan this should typically be 2.
  ///
  /// Expected path (per your notes): `entitlements.perks.ads.interstitial_every_songs`.
  final int? interstitialEverySongs;

  final bool? backgroundPlayEnabled;
  final bool? downloadsEnabled;
  final bool? videoDownloadsEnabled;
  final bool? playlistsCreateEnabled;
  final bool? playlistsMixEnabled;

  /// Optional hint for the audio tier (e.g. 320 kbps). Your player decides how
  /// to interpret this.
  final int? maxAudioKbps;
  final int? maxSkipsPerHour;
  final GiftAccessTier? giftingTier;
  final bool? vipBadgeEnabled;
  final bool? highlightedCommentsEnabled;
  final bool? exclusiveContentEnabled;
  final bool? priorityLiveAccessEnabled;
  final bool? songRequestsEnabled;
  final bool? earlyAccessEnabled;

  /// Content access intent: limited | standard | exclusive
  final String? contentAccess;

  /// Content limit ratio for limited access (e.g. 0.3 for Free).
  final double? contentLimitRatio;

  /// Battles access intent / priority: limited | standard | priority
  final String? battlePriority;

  final bool? featured;

  final int? monthlyFreeCoins;
  final int? weeklyFreeCoins;
  final int? monthlyBonusCoins;

  bool get effectiveAdsEnabled => adsEnabled ?? true;

  int get effectiveInterstitialEverySongs {
    final v = interstitialEverySongs;
    if (v == null) return 2;
    if (v <= 0) return 0;
    return v;
  }

  bool get effectiveBackgroundPlayEnabled => backgroundPlayEnabled ?? false;
  bool get effectiveDownloadsEnabled => downloadsEnabled ?? false;
  bool get effectiveVideoDownloadsEnabled => videoDownloadsEnabled ?? false;
  bool get effectivePlaylistsCreateEnabled => playlistsCreateEnabled ?? false;
  bool get effectivePlaylistsMixEnabled => playlistsMixEnabled ?? false;

  int get effectiveMaxSkipsPerHour {
    final v = maxSkipsPerHour;
    if (v == null) return 6;
    if (v < 0) return -1;
    return v.clamp(0, 100000000);
  }

  bool get hasUnlimitedSkips => effectiveMaxSkipsPerHour < 0;

  GiftAccessTier get effectiveGiftingTier =>
      giftingTier ?? GiftAccessTier.limited;

  bool canSendGiftTier(GiftAccessTier requiredTier) {
    return giftAccessTierAllows(effectiveGiftingTier, requiredTier);
  }

  bool get effectiveVipBadgeEnabled => vipBadgeEnabled ?? false;
  bool get effectiveHighlightedCommentsEnabled =>
      highlightedCommentsEnabled ?? false;
  bool get effectiveExclusiveContentEnabled =>
      exclusiveContentEnabled ?? effectiveContentAccess == 'exclusive';
  bool get effectivePriorityLiveAccessEnabled =>
      priorityLiveAccessEnabled ?? false;
  bool get effectiveSongRequestsEnabled => songRequestsEnabled ?? false;
  bool get effectiveEarlyAccessEnabled => earlyAccessEnabled ?? false;

  bool get effectiveHighQualityAudioEnabled {
    final max = maxAudioKbps;
    if (max != null && max >= 320) return true;

    final quality =
        (getStringPath('perks.audio.quality') ??
                getStringPath('features.quality.audio') ??
                '')
            .trim()
            .toLowerCase();
    return quality == 'high' || quality == 'studio' || quality == 'lossless';
  }

  String get effectiveContentAccess =>
      (contentAccess ?? 'limited').trim().isEmpty
      ? 'limited'
      : contentAccess!.trim();
  double get effectiveContentLimitRatio {
    final v = contentLimitRatio;
    if (v == null) return 0.3;
    if (v.isNaN) return 0.3;
    return v.clamp(0.0, 1.0);
  }

  String get effectiveBattlePriority =>
      (battlePriority ?? 'limited').trim().isEmpty
      ? 'limited'
      : battlePriority!.trim();
  bool get effectiveFeatured => featured ?? false;
  int get effectiveMonthlyFreeCoins =>
      (monthlyFreeCoins ?? 0).clamp(0, 100000000);
  int get effectiveWeeklyFreeCoins =>
      (weeklyFreeCoins ?? 0).clamp(0, 100000000);
  int get effectiveMonthlyBonusCoins =>
      (monthlyBonusCoins ?? monthlyFreeCoins ?? 0).clamp(0, 100000000);

  /// Reads a nested value from [raw] using dotted paths.
  ///
  /// Example: `perks.ads.interstitial_every_songs`.
  dynamic getPath(String path) {
    dynamic current = raw;
    for (final part in path.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  bool? getBoolPath(String path) {
    final v = getPath(path);
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  int? getIntPath(String path) {
    final v = getPath(path);
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  double? getDoublePath(String path) {
    final v = getPath(path);
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  String? getStringPath(String path) {
    final v = getPath(path);
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  _CreatorTier? _fallbackCreatorTier(String? fallbackPlanId) {
    final id = canonicalPlanId((fallbackPlanId ?? '').trim());
    if (id.isEmpty) return null;
    if (!(id.startsWith('artist_') || id.startsWith('dj_'))) return null;

    if (id.contains('starter') || id.contains('free')) {
      return _CreatorTier.starter;
    }
    if (id.contains('pro')) {
      return _CreatorTier.pro;
    }
    if (id.contains('premium') || id.contains('platinum')) {
      return _CreatorTier.premium;
    }
    return null;
  }

  int? _fallbackTrackUploadLimit(String creatorRole, String? fallbackPlanId) {
    final role = creatorRole.trim().toLowerCase();
    if (role != 'artist' && role != 'dj') return null;
    final tier = _fallbackCreatorTier(fallbackPlanId);
    if (tier == null) return null;

    switch (tier) {
      case _CreatorTier.starter:
        return 5;
      case _CreatorTier.pro:
      case _CreatorTier.premium:
        return -1;
    }
  }

  int? _fallbackVideoUploadLimit(String creatorRole, String? fallbackPlanId) {
    final role = creatorRole.trim().toLowerCase();
    if (role != 'artist' && role != 'dj') return null;
    final tier = _fallbackCreatorTier(fallbackPlanId);
    if (tier == null) return null;

    switch (tier) {
      case _CreatorTier.starter:
        return 5;
      case _CreatorTier.pro:
        return 30;
      case _CreatorTier.premium:
        return -1;
    }
  }

  bool? _fallbackCreatorPaid(String? fallbackPlanId) {
    final tier = _fallbackCreatorTier(fallbackPlanId);
    if (tier == null) return null;
    return tier != _CreatorTier.starter;
  }

  int? creatorTrackUploadLimit(String creatorRole, {String? fallbackPlanId}) {
    final role = creatorRole.trim().toLowerCase();
    final rolePaths = switch (role) {
      'artist' => <String>['uploads.songs'],
      // Legacy/stale plans may still expose DJ track limit under `songs`.
      'dj' => <String>['uploads.mixes', 'uploads.songs'],
      _ => null,
    };
    if (rolePaths == null) return null;

    final explicit = _creatorLimitFromPaths([
      for (final path in rolePaths) 'features.creator.$path',
      for (final path in rolePaths) 'perks.creator.$path',
      'features.uploads',
      'features.upload_limit',
    ]);
    return explicit ?? _fallbackTrackUploadLimit(role, fallbackPlanId);
  }

  int? creatorVideoUploadLimit(String creatorRole, {String? fallbackPlanId}) {
    final role = creatorRole.trim().toLowerCase();
    final explicit = _creatorLimitFromPaths([
      'features.creator.uploads.videos',
      'perks.creator.uploads.videos',
      'features.video_uploads',
      'features.video_upload_limit',
    ]);
    return explicit ?? _fallbackVideoUploadLimit(role, fallbackPlanId);
  }

  bool creatorCanGoLive({String? fallbackPlanId}) {
    final explicit =
        getBoolPath('features.creator.live.host') ??
        getBoolPath('features.creator.live.enabled') ??
        getBoolPath('perks.creator.live.host') ??
        getBoolPath('perks.creator.live.enabled') ??
        getBoolPath('features.creator.monetization.live') ??
        getBoolPath('perks.creator.monetization.live') ??
        getBoolPath('features.live') ??
        getBoolPath('features.can_host_live');

    if (explicit != null) return explicit;
    return _fallbackCreatorPaid(fallbackPlanId) ?? false;
  }

  bool creatorCanBattle({String? fallbackPlanId}) {
    final explicit =
        getBoolPath('features.creator.live.battles') ??
        getBoolPath('perks.creator.live.battles') ??
        getBoolPath('features.creator.monetization.battles') ??
        getBoolPath('perks.creator.monetization.battles') ??
        getBoolPath('features.battles.enabled') ??
        getBoolPath('perks.battles.enabled') ??
        getBoolPath('features.battles');

    if (explicit != null) return explicit;
    return _fallbackCreatorPaid(fallbackPlanId) ?? false;
  }

  bool creatorCanMonetize({String? fallbackPlanId}) {
    final explicitFlags = <bool?>[
      getBoolPath('features.creator.monetization'),
      getBoolPath('features.creator.monetization.streams'),
      getBoolPath('features.creator.monetization.coins'),
      getBoolPath('features.creator.monetization.live'),
      getBoolPath('features.creator.monetization.live_gifts'),
      getBoolPath('features.creator.monetization.battles'),
      getBoolPath('features.creator.monetization.fan_support'),
      getBoolPath('perks.creator.monetization.enabled'),
      getBoolPath('perks.creator.monetization.streams'),
      getBoolPath('perks.creator.monetization.coins'),
      getBoolPath('perks.creator.monetization.live'),
      getBoolPath('perks.creator.monetization.live_gifts'),
      getBoolPath('perks.creator.monetization.battles'),
      getBoolPath('perks.creator.monetization.fan_support'),
      getBoolPath('features.monetization'),
    ].whereType<bool>().toList(growable: false);
    if (explicitFlags.isNotEmpty) {
      return explicitFlags.any((value) => value);
    }

    return _fallbackCreatorPaid(fallbackPlanId) ?? false;
  }

  String creatorWithdrawalAccess({String? fallbackPlanId}) {
    final explicit =
        getStringPath('features.creator.withdrawals.access') ??
        getStringPath('perks.creator.withdrawals.access') ??
        getStringPath('features.withdrawals.access') ??
        getStringPath('perks.withdrawals.access');
    if (explicit != null) return explicit;

    final explicitEnabled =
        getBoolPath('features.creator.withdrawals') ??
        getBoolPath('features.creator.withdrawals.enabled') ??
        getBoolPath('perks.creator.withdrawals.enabled') ??
        getBoolPath('features.withdrawals');
    if (explicitEnabled != null) {
      return explicitEnabled ? 'limited' : 'none';
    }

    final tier = _fallbackCreatorTier(fallbackPlanId);
    switch (tier) {
      case _CreatorTier.pro:
        return 'limited';
      case _CreatorTier.premium:
        return 'unlimited';
      case _CreatorTier.starter:
      case null:
        return 'none';
    }
  }

  bool creatorCanWithdraw({String? fallbackPlanId}) {
    return creatorWithdrawalAccess(fallbackPlanId: fallbackPlanId) != 'none';
  }

  bool creatorIsVerified() {
    final explicit =
        getBoolPath('features.creator.profile.verified_badge') ??
        getBoolPath('perks.creator.profile.verified_badge') ??
        getBoolPath('features.verification') ??
        getBoolPath('perks.badges.verified');
    return explicit ?? false;
  }

  int? _creatorLimitFromPaths(List<String> paths) {
    for (final path in paths) {
      final limit = _parseCreatorLimitValue(getPath(path));
      if (limit != null) return limit;
    }
    return null;
  }

  int? _parseCreatorLimitValue(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final number = value.round();
      return number < 0 ? -1 : number;
    }

    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized == 'unlimited' ||
        normalized == 'all' ||
        normalized == 'infinity') {
      return -1;
    }

    final parsed = int.tryParse(normalized);
    if (parsed == null) return null;
    return parsed < 0 ? -1 : parsed;
  }

  static Entitlements fromJson(Map<String, dynamic> json) {
    bool? adsEnabled;
    final ads = json['ads_enabled'];
    if (ads is bool) adsEnabled = ads;

    int? interstitialEverySongs;
    final directInterstitialEverySongs = json['interstitial_every_songs'];
    if (directInterstitialEverySongs is num) {
      interstitialEverySongs = directInterstitialEverySongs.round();
    }
    if (directInterstitialEverySongs is String) {
      interstitialEverySongs = int.tryParse(directInterstitialEverySongs);
    }

    final perks = json['perks'];
    if (perks is Map) {
      final adsPerks = perks['ads'];
      if (adsPerks is Map) {
        final raw = adsPerks['interstitial_every_songs'];
        if (raw is num) interstitialEverySongs = raw.round();
        if (raw is String) interstitialEverySongs = int.tryParse(raw);
      }
    }

    // Additional perks (nested) used for feature gating.
    bool? backgroundPlayEnabled;
    bool? downloadsEnabled;
    bool? videoDownloadsEnabled;
    bool? playlistsCreateEnabled;
    bool? playlistsMixEnabled;
    int? maxAudioKbps;
    int? maxSkipsPerHour;
    GiftAccessTier? giftingTier;
    bool? vipBadgeEnabled;
    bool? highlightedCommentsEnabled;
    bool? exclusiveContentEnabled;
    bool? priorityLiveAccessEnabled;
    bool? songRequestsEnabled;
    bool? earlyAccessEnabled;
    String? contentAccess;
    double? contentLimitRatio;
    String? battlePriority;
    bool? featured;
    int? monthlyFreeCoins;
    int? weeklyFreeCoins;
    int? monthlyBonusCoins;

    dynamic readPath(String path) {
      dynamic current = json;
      for (final part in path.split('.')) {
        if (current is Map && current.containsKey(part)) {
          current = current[part];
        } else {
          return null;
        }
      }
      return current;
    }

    bool? readBool(String path) {
      final v = readPath(path);
      if (v is bool) return v;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true') return true;
        if (s == 'false') return false;
      }
      return null;
    }

    int? readInt(String path) {
      final v = readPath(path);
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    double? readDouble(String path) {
      final v = readPath(path);
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
      return null;
    }

    String? readString(String path) {
      final v = readPath(path);
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? bitrateFromQuality(String? quality) {
      switch ((quality ?? '').trim().toLowerCase()) {
        case 'high':
          return 320;
        case 'studio':
        case 'lossless':
          return 320;
        default:
          return null;
      }
    }

    String? contentAccessFromExclusiveContent(String? value) {
      switch ((value ?? '').trim().toLowerCase()) {
        case 'full':
        case 'exclusive':
          return 'exclusive';
        case 'early_releases':
        case 'standard':
          return 'standard';
        case 'none':
        case 'limited':
          return 'limited';
        default:
          return null;
      }
    }

    backgroundPlayEnabled =
        readBool('perks.playback.background_play') ??
        readBool('perks.playback.background_play_enabled');
    downloadsEnabled =
        readBool('perks.downloads.enabled') ??
        readBool('perks.downloads.offline_enabled');
    videoDownloadsEnabled =
        readBool('perks.downloads.video_enabled') ??
        readBool('perks.downloads.video_downloads') ??
        readBool('perks.video_downloads');
    playlistsCreateEnabled = readBool('perks.playlists.create');
    playlistsMixEnabled = readBool('perks.playlists.mix');
    adsEnabled = adsEnabled ?? readBool('perks.ads.enabled');
    maxAudioKbps =
        readInt('perks.audio.max_kbps') ??
        readInt('perks.audio.max_bitrate_kbps');
    maxSkipsPerHour =
        readInt('perks.playback.skips_per_hour') ??
        readInt('perks.playback.skip_limit_per_hour') ??
        readInt('perks.skips_per_hour');
    giftingTier = giftAccessTierFromString(
      readString('perks.engagement.gifting.tier') ??
          readString('perks.gifting.tier') ??
          readString('perks.live.gifts.tier') ??
          readString('perks.gifting'),
    );
    vipBadgeEnabled =
        readBool('perks.recognition.vip_badge') ??
        readBool('perks.profile.vip_badge') ??
        readBool('perks.vip_badge');
    highlightedCommentsEnabled =
        readBool('perks.live.highlighted_comments') ??
        readBool('perks.comments.highlighted') ??
        readBool('perks.highlighted_comments');
    exclusiveContentEnabled =
        readBool('perks.content.exclusive') ??
        readBool('perks.exclusive_content');
    priorityLiveAccessEnabled =
        readBool('perks.live.priority_access') ??
        readBool('perks.priority_live_access');
    songRequestsEnabled =
        readBool('perks.live.song_requests.enabled') ??
        readBool('perks.song_requests.enabled') ??
        readBool('perks.song_requests');
    earlyAccessEnabled =
        readBool('perks.content.early_access') ??
        readBool('perks.early_access');
    contentAccess =
        readString('perks.content_access') ??
        readString('perks.content.access');
    contentLimitRatio =
        readDouble('perks.content_limit_ratio') ??
        readDouble('perks.content.limit_ratio');
    battlePriority =
        readString('perks.battles.priority') ??
        readString('perks.battles.access');
    featured = readBool('perks.featured') ?? readBool('perks.featured_status');
    monthlyFreeCoins = readInt('perks.coins.monthly_free.amount');
    weeklyFreeCoins = readInt('perks.coins.weekly_free.amount');
    monthlyBonusCoins =
        readInt('perks.coins.monthly_bonus.amount') ??
        readInt('perks.monthly_bonus_coins');

    // subscription_plans.features is returned from `/api/subscriptions/me`
    // under `entitlements.features` and should drive listener feature gating.
    interstitialEverySongs =
        interstitialEverySongs ??
        readInt('features.ads.interstitial_every_songs');
    backgroundPlayEnabled =
        backgroundPlayEnabled ??
        readBool('features.playback.background_play') ??
        readBool('features.background_play');
    downloadsEnabled =
        downloadsEnabled ??
        readBool('features.downloads.enabled') ??
        readBool('features.downloads.offline_listening') ??
        readBool('features.downloads_enabled');
    videoDownloadsEnabled =
        videoDownloadsEnabled ??
        readBool('features.downloads.video_enabled') ??
        readBool('features.downloads.video_downloads') ??
        readBool('features.video_downloads');
    playlistsCreateEnabled =
        playlistsCreateEnabled ?? readBool('features.playlists.create');
    playlistsMixEnabled =
        playlistsMixEnabled ?? readBool('features.playlists.mix');
    adsEnabled = adsEnabled ?? readBool('features.ads.enabled');
    maxAudioKbps =
        maxAudioKbps ??
        readInt('features.quality.audio_max_kbps') ??
        readInt('features.audio_max_kbps') ??
        bitrateFromQuality(readString('features.quality.audio')) ??
        bitrateFromQuality(readString('features.audio_quality'));
    maxSkipsPerHour =
        maxSkipsPerHour ??
        readInt('features.playback.skips_per_hour') ??
        readInt('features.skips_per_hour');
    giftingTier =
        giftingTier ??
        giftAccessTierFromString(
          readString('features.engagement.gifting.tier') ??
              readString('features.gifting.tier') ??
              readString('features.live.gifts.tier') ??
              readString('features.gifting'),
        );
    vipBadgeEnabled =
        vipBadgeEnabled ??
        readBool('features.recognition.vip_badge') ??
        readBool('features.profile.vip_badge') ??
        readBool('features.vip_badge');
    highlightedCommentsEnabled =
        highlightedCommentsEnabled ??
        readBool('features.live.highlighted_comments') ??
        readBool('features.comments.highlighted') ??
        readBool('features.highlighted_comments');
    exclusiveContentEnabled =
        exclusiveContentEnabled ??
        readBool('features.content.exclusive') ??
        readBool('features.exclusive_content');
    priorityLiveAccessEnabled =
        priorityLiveAccessEnabled ??
        readBool('features.live.priority_access') ??
        readBool('features.priority_live_access');
    songRequestsEnabled =
        songRequestsEnabled ??
        readBool('features.live.song_requests.enabled') ??
        readBool('features.song_requests.enabled') ??
        readBool('features.song_requests');
    earlyAccessEnabled =
        earlyAccessEnabled ??
        readBool('features.content.early_access') ??
        readBool('features.early_access');
    contentAccess =
        contentAccess ??
        readString('features.content_access') ??
        contentAccessFromExclusiveContent(
          readString('features.exclusive_content'),
        );
    contentLimitRatio =
        contentLimitRatio ?? readDouble('features.content_limit_ratio');
    battlePriority =
        battlePriority ??
        readString('features.battles.priority') ??
        readString('features.battles.access');
    featured =
        featured ??
        readBool('features.featured') ??
        readBool('features.featured_status');
    monthlyFreeCoins =
        monthlyFreeCoins ?? readInt('features.coins.monthly_free.amount');
    weeklyFreeCoins =
        weeklyFreeCoins ?? readInt('features.coins.weekly_free.amount');
    monthlyBonusCoins =
        monthlyBonusCoins ??
        readInt('features.coins.monthly_bonus.amount') ??
        readInt('features.monthly_bonus_coins');

    return Entitlements(
      raw: json,
      adsEnabled: adsEnabled,
      interstitialEverySongs: interstitialEverySongs,
      backgroundPlayEnabled: backgroundPlayEnabled,
      downloadsEnabled: downloadsEnabled,
      videoDownloadsEnabled: videoDownloadsEnabled,
      playlistsCreateEnabled: playlistsCreateEnabled,
      playlistsMixEnabled: playlistsMixEnabled,
      maxAudioKbps: maxAudioKbps,
      maxSkipsPerHour: maxSkipsPerHour,
      giftingTier: giftingTier,
      vipBadgeEnabled: vipBadgeEnabled,
      highlightedCommentsEnabled: highlightedCommentsEnabled,
      exclusiveContentEnabled: exclusiveContentEnabled,
      priorityLiveAccessEnabled: priorityLiveAccessEnabled,
      songRequestsEnabled: songRequestsEnabled,
      earlyAccessEnabled: earlyAccessEnabled,
      contentAccess: contentAccess,
      contentLimitRatio: contentLimitRatio,
      battlePriority: battlePriority,
      featured: featured,
      monthlyFreeCoins: monthlyFreeCoins,
      weeklyFreeCoins: weeklyFreeCoins,
      monthlyBonusCoins: monthlyBonusCoins,
    );
  }

  static Entitlements defaultsForPlanId(String planId) {
    final id = canonicalPlanId(planId);
    final isPremium = id == 'premium' || id.startsWith('premium_');
    final isPlatinum = id == 'platinum' || id.startsWith('platinum_');
    final isFamily = id == 'family' || id.startsWith('family_');

    final isArtistStarter =
        id == 'artist_starter' ||
        id == 'artist_free' ||
        id.startsWith('artist_starter_') ||
        id.startsWith('artist_free_');
    final isArtistPro = id == 'artist_pro' || id.startsWith('artist_pro_');
    final isArtistPremium =
        id == 'artist_premium' || id.startsWith('artist_premium_');
    final isDjStarter =
        id == 'dj_starter' ||
        id == 'dj_free' ||
        id.startsWith('dj_starter_') ||
        id.startsWith('dj_free_');
    final isDjPro = id == 'dj_pro' || id.startsWith('dj_pro_');
    final isDjPremium = id == 'dj_premium' || id.startsWith('dj_premium_');

    if (isArtistPremium) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'artist',
              'tier': 'platinum',
              'uploads': {'songs': -1, 'videos': -1, 'bulk_upload': true},
              'quality': {'audio': 'studio', 'video': 'hd'},
              'analytics': {
                'level': 'advanced',
                'views': true,
                'likes': true,
                'comments': true,
                'revenue': true,
                'watch_time': true,
                'countries': true,
              },
              'monetization': {
                'streams': true,
                'coins': true,
                'live': true,
                'battles': true,
                'fan_support': true,
              },
              'withdrawals': {'access': 'unlimited'},
              'live': {'host': true, 'battles': true, 'multi_guest': true},
              'visibility': {
                'boost': 'high',
                'featured_sections': ['trending', 'recommended', 'top_artists'],
              },
              'profile': {
                'customization': true,
                'verified_badge': true,
                'pin_content': true,
              },
              'marketing': {'promote_content': true, 'push_to_fans': true},
              'ads_on_content': 'none',
            },
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'battles': {'enabled': true, 'priority': 'priority'},
            'content_access': 'exclusive',
            'quality': {
              'audio': 'studio',
              'audio_max_kbps': 320,
              'audio_max_bit_depth': 24,
              'audio_max_sample_rate_khz': 44.1,
            },
            'featured': true,
          },
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true, 'video_enabled': true},
            'playlists': {'create': true, 'mix': true},
            'quality': {
              'audio': 'studio',
              'audio_max_kbps': 320,
              'audio_max_bit_depth': 24,
              'audio_max_sample_rate_khz': 44.1,
            },
            'gifting': {'tier': 'vip'},
            'live': {
              'song_requests': {'enabled': true},
              'priority_access': true,
              'highlighted_comments': true,
            },
            'recognition': {'vip_badge': true},
            'content': {'exclusive': true, 'early_access': true},
            'content_access': 'exclusive',
            'battles': {'priority': 'priority'},
            'featured': true,
            'coins': {
              'monthly_free': {'amount': 200},
              'monthly_bonus': {'amount': 200},
              'weekly_free': {'amount': 50},
            },
            'creator': {
              'type': 'artist',
              'uploads': {
                'songs': 'unlimited',
                'videos': 'unlimited',
                'bulk_upload': true,
              },
              'monetization': {
                'streams': true,
                'coins': true,
                'live': true,
                'battles': true,
                'fan_support': true,
              },
              'withdrawals': {'access': 'unlimited'},
              'live': {'enabled': true, 'battles': true, 'multi_guest': true},
              'visibility': {'boost': 'high'},
              'profile': {
                'customization': true,
                'verified_badge': true,
                'pin_content': true,
              },
              'marketing': {'promote_content': true, 'push_to_fans': true},
            },
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: true,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: true,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.vip,
        vipBadgeEnabled: true,
        highlightedCommentsEnabled: true,
        exclusiveContentEnabled: true,
        priorityLiveAccessEnabled: true,
        songRequestsEnabled: true,
        earlyAccessEnabled: true,
        contentAccess: 'exclusive',
        battlePriority: 'priority',
        featured: true,
        monthlyFreeCoins: 200,
        weeklyFreeCoins: 50,
        monthlyBonusCoins: 200,
      );
    }

    if (isDjPremium) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'dj',
              'tier': 'platinum',
              'uploads': {'mixes': -1, 'bulk_upload': true},
              'analytics': {
                'level': 'advanced',
                'views': true,
                'likes': true,
                'comments': true,
                'revenue': true,
                'watch_time': true,
                'countries': true,
              },
              'monetization': {
                'live_gifts': true,
                'battles': true,
                'streams': true,
                'fan_support': true,
              },
              'withdrawals': {'access': 'unlimited'},
              'live': {
                'host': true,
                'battles': true,
                'audience_voting': true,
                'rewards': true,
              },
              'visibility': {
                'boost': 'high',
                'featured_sections': ['live_now', 'top_djs'],
              },
              'profile': {
                'customization': true,
                'verified_badge': true,
                'pin_content': true,
              },
              'ads_on_content': 'none',
            },
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'battles': {'enabled': true, 'priority': 'priority'},
            'content_access': 'exclusive',
            'quality': {
              'audio': 'studio',
              'audio_max_kbps': 320,
              'audio_max_bit_depth': 24,
              'audio_max_sample_rate_khz': 44.1,
            },
            'featured': true,
          },
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true, 'video_enabled': true},
            'playlists': {'create': true, 'mix': true},
            'quality': {
              'audio': 'studio',
              'audio_max_kbps': 320,
              'audio_max_bit_depth': 24,
              'audio_max_sample_rate_khz': 44.1,
            },
            'gifting': {'tier': 'vip'},
            'live': {
              'song_requests': {'enabled': true},
              'priority_access': true,
              'highlighted_comments': true,
            },
            'recognition': {'vip_badge': true},
            'content': {'exclusive': true, 'early_access': true},
            'content_access': 'exclusive',
            'battles': {'priority': 'priority'},
            'featured': true,
            'coins': {
              'monthly_free': {'amount': 200},
              'monthly_bonus': {'amount': 200},
              'weekly_free': {'amount': 50},
            },
            'creator': {
              'type': 'dj',
              'uploads': {'mixes': 'unlimited', 'bulk_upload': true},
              'monetization': {
                'live_gifts': true,
                'battles': true,
                'streams': true,
                'fan_support': true,
              },
              'withdrawals': {'access': 'unlimited'},
              'live': {
                'enabled': true,
                'battles': true,
                'audience_voting': true,
                'rewards': true,
              },
              'visibility': {'boost': 'high'},
              'profile': {
                'customization': true,
                'verified_badge': true,
                'pin_content': true,
              },
            },
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: true,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: true,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.vip,
        vipBadgeEnabled: true,
        highlightedCommentsEnabled: true,
        exclusiveContentEnabled: true,
        priorityLiveAccessEnabled: true,
        songRequestsEnabled: true,
        earlyAccessEnabled: true,
        contentAccess: 'exclusive',
        battlePriority: 'priority',
        featured: true,
        monthlyFreeCoins: 200,
        weeklyFreeCoins: 50,
        monthlyBonusCoins: 200,
      );
    }

    if (isArtistPro) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'artist',
              'tier': 'premium',
              'uploads': {'songs': 20, 'videos': 5, 'bulk_upload': false},
              'quality': {'audio': 'high', 'video': 'hd'},
              'analytics': {
                'level': 'medium',
                'views': true,
                'likes': true,
                'comments': true,
                'revenue': true,
                'watch_time': false,
                'countries': false,
              },
              'monetization': {
                'streams': true,
                'coins': true,
                'live': true,
                'battles': true,
                'fan_support': false,
              },
              'withdrawals': {'access': 'limited'},
              'live': {'host': true, 'battles': true, 'multi_guest': false},
              'visibility': {'boost': 'small', 'featured_sections': []},
              'profile': {
                'customization': true,
                'verified_badge': false,
                'pin_content': false,
              },
              'marketing': {'promote_content': false, 'push_to_fans': false},
              'ads_on_content': 'reduced',
            },
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'battles': {'enabled': true, 'priority': 'standard'},
            'content_access': 'standard',
            'quality': {'audio': 'high', 'audio_max_kbps': 320},
          },
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true},
            'playlists': {'create': true, 'mix': false},
            'quality': {'audio': 'high', 'audio_max_kbps': 320},
            'gifting': {'tier': 'standard'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': true},
            'content_access': 'standard',
            'battles': {'priority': 'standard'},
            'creator': {
              'type': 'artist',
              'uploads': {'songs': 20, 'videos': 5},
              'monetization': {'streams': true, 'coins': true},
              'withdrawals': {'access': 'limited'},
              'live': {'enabled': true, 'battles': true},
              'visibility': {'boost': 'small'},
              'profile': {'customization': true, 'verified_badge': false},
            },
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: false,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.standard,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: true,
        contentAccess: 'standard',
        battlePriority: 'standard',
        monthlyBonusCoins: 0,
      );
    }

    if (isDjPro) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'dj',
              'tier': 'premium',
              'uploads': {'mixes': -1, 'bulk_upload': false},
              'analytics': {
                'level': 'medium',
                'views': true,
                'likes': true,
                'comments': true,
                'revenue': true,
              },
              'monetization': {
                'live_gifts': true,
                'battles': true,
                'streams': true,
              },
              'withdrawals': {'access': 'limited'},
              'live': {'host': true, 'battles': true},
              'visibility': {'boost': 'small', 'featured_sections': []},
              'profile': {'customization': true, 'verified_badge': false},
              'ads_on_content': 'reduced',
            },
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'battles': {'enabled': true, 'priority': 'standard'},
            'content_access': 'standard',
            'quality': {'audio': 'high', 'audio_max_kbps': 320},
          },
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true},
            'playlists': {'create': true, 'mix': false},
            'quality': {'audio': 'high', 'audio_max_kbps': 320},
            'gifting': {'tier': 'standard'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': true},
            'content_access': 'standard',
            'battles': {'priority': 'standard'},
            'creator': {
              'type': 'dj',
              'uploads': {'mixes': 'unlimited'},
              'monetization': {'live_gifts': true, 'streams': true},
              'withdrawals': {'access': 'limited'},
              'live': {'enabled': true, 'battles': true},
              'visibility': {'boost': 'small'},
              'profile': {'customization': true, 'verified_badge': false},
            },
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: false,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.standard,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: true,
        contentAccess: 'standard',
        battlePriority: 'standard',
        monthlyBonusCoins: 0,
      );
    }

    if (isArtistStarter) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'artist',
              'tier': 'free',
              'uploads': {'songs': 5, 'videos': 5, 'bulk_upload': false},
              'quality': {'audio': 'standard', 'video': 'standard'},
              'analytics': {
                'level': 'basic',
                'views': true,
                'likes': true,
                'comments': false,
                'revenue': false,
                'watch_time': false,
                'countries': false,
              },
              'monetization': {
                'streams': false,
                'coins': false,
                'live': false,
                'battles': true,
                'fan_support': false,
              },
              'withdrawals': {'access': 'none'},
              'live': {'host': false, 'battles': true, 'multi_guest': false},
              'visibility': {'boost': 'none', 'featured_sections': []},
              'profile': {
                'customization': false,
                'verified_badge': false,
                'pin_content': false,
              },
              'marketing': {'promote_content': false, 'push_to_fans': false},
              'ads_on_content': 'full',
            },
            'ads': {'enabled': true, 'interstitial_every_songs': 2},
            'battles': {'enabled': true, 'priority': 'none'},
            'content_access': 'limited',
            'content_limit_ratio': 0.3,
          },
          'perks': {
            'ads': {'enabled': true, 'interstitial_every_songs': 2},
            'playback': {'background_play': false, 'skips_per_hour': 6},
            'downloads': {'enabled': false},
            'playlists': {'create': false, 'mix': false},
            'quality': {'audio': 'low'},
            'gifting': {'tier': 'limited'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': false},
            'content_access': 'limited',
            'content_limit_ratio': 0.3,
            'battles': {'priority': 'limited'},
            'creator': {
              'type': 'artist',
              'uploads': {'songs': 5, 'videos': 5},
              'monetization': {'enabled': false},
              'withdrawals': {'access': 'none'},
              'live': {'enabled': false, 'battles': true},
              'visibility': {'boost': 'none'},
              'profile': {'customization': false, 'verified_badge': false},
            },
          },
        },
        adsEnabled: true,
        interstitialEverySongs: 2,
        backgroundPlayEnabled: false,
        downloadsEnabled: false,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: false,
        playlistsMixEnabled: false,
        maxSkipsPerHour: 6,
        giftingTier: GiftAccessTier.limited,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: false,
        contentAccess: 'limited',
        contentLimitRatio: 0.3,
        battlePriority: 'limited',
        featured: false,
        monthlyFreeCoins: 0,
        weeklyFreeCoins: 0,
        monthlyBonusCoins: 0,
      );
    }

    if (isDjStarter) {
      return const Entitlements(
        raw: {
          'features': {
            'creator': {
              'audience': 'dj',
              'tier': 'free',
              'uploads': {'mixes': 5, 'videos': 5, 'bulk_upload': false},
              'analytics': {
                'level': 'basic',
                'views': true,
                'likes': true,
                'comments': false,
                'revenue': false,
              },
              'monetization': {
                'live_gifts': false,
                'battles': true,
                'streams': false,
              },
              'withdrawals': {'access': 'none'},
              'live': {'host': false, 'battles': true},
              'visibility': {'boost': 'none', 'featured_sections': []},
              'profile': {'customization': false, 'verified_badge': false},
              'ads_on_content': 'full',
            },
            'ads': {'enabled': true, 'interstitial_every_songs': 2},
            'battles': {'enabled': true, 'priority': 'none'},
            'content_access': 'limited',
            'content_limit_ratio': 0.3,
          },
          'perks': {
            'ads': {'enabled': true, 'interstitial_every_songs': 2},
            'playback': {'background_play': false, 'skips_per_hour': 6},
            'downloads': {'enabled': false},
            'playlists': {'create': false, 'mix': false},
            'quality': {'audio': 'low'},
            'gifting': {'tier': 'limited'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': false},
            'content_access': 'limited',
            'content_limit_ratio': 0.3,
            'battles': {'priority': 'limited'},
            'creator': {
              'type': 'dj',
              'uploads': {'mixes': 5, 'videos': 5},
              'monetization': {'enabled': false},
              'withdrawals': {'access': 'none'},
              'live': {'enabled': false, 'battles': true},
              'visibility': {'boost': 'none'},
              'profile': {'customization': false, 'verified_badge': false},
            },
          },
        },
        adsEnabled: true,
        interstitialEverySongs: 2,
        backgroundPlayEnabled: false,
        downloadsEnabled: false,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: false,
        playlistsMixEnabled: false,
        maxSkipsPerHour: 6,
        giftingTier: GiftAccessTier.limited,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: false,
        contentAccess: 'limited',
        contentLimitRatio: 0.3,
        battlePriority: 'limited',
        featured: false,
        monthlyFreeCoins: 0,
        weeklyFreeCoins: 0,
        monthlyBonusCoins: 0,
      );
    }

    if (isPlatinum || isFamily || isArtistPremium || isDjPremium) {
      return const Entitlements(
        raw: {
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true, 'video_enabled': true},
            'playlists': {'create': true, 'mix': true},
            'quality': {
              'audio': 'studio',
              'audio_max_kbps': 320,
              'audio_max_bit_depth': 24,
              'audio_max_sample_rate_khz': 44.1,
            },
            'gifting': {'tier': 'vip'},
            'live': {
              'song_requests': {'enabled': true},
              'priority_access': true,
              'highlighted_comments': true,
            },
            'recognition': {'vip_badge': true},
            'content': {'exclusive': true, 'early_access': true},
            'content_access': 'exclusive',
            'battles': {'priority': 'priority'},
            'featured': true,
            'coins': {
              'monthly_free': {'amount': 200},
              'monthly_bonus': {'amount': 200},
              'weekly_free': {'amount': 50},
            },
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: true,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: true,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.vip,
        vipBadgeEnabled: true,
        highlightedCommentsEnabled: true,
        exclusiveContentEnabled: true,
        priorityLiveAccessEnabled: true,
        songRequestsEnabled: true,
        earlyAccessEnabled: true,
        contentAccess: 'exclusive',
        battlePriority: 'priority',
        featured: true,
        monthlyFreeCoins: 200,
        weeklyFreeCoins: 50,
        monthlyBonusCoins: 200,
      );
    }

    if (isPremium) {
      return const Entitlements(
        raw: {
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'playback': {'background_play': true, 'skips_per_hour': -1},
            'downloads': {'enabled': true},
            'playlists': {'create': true, 'mix': false},
            'quality': {'audio': 'high', 'audio_max_kbps': 320},
            'gifting': {'tier': 'standard'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': true},
            'content_access': 'standard',
            'battles': {'priority': 'standard'},
          },
        },
        adsEnabled: false,
        interstitialEverySongs: 0,
        backgroundPlayEnabled: true,
        downloadsEnabled: true,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: true,
        playlistsMixEnabled: false,
        maxAudioKbps: 320,
        maxSkipsPerHour: -1,
        giftingTier: GiftAccessTier.standard,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: true,
        contentAccess: 'standard',
        battlePriority: 'standard',
        monthlyBonusCoins: 0,
      );
    }

    if (isFreeLikePlanId(id)) {
      return const Entitlements(
        raw: {
          'perks': {
            'ads': {'enabled': true, 'interstitial_every_songs': 2},
            'playback': {'background_play': false, 'skips_per_hour': 6},
            'downloads': {'enabled': false},
            'playlists': {'create': false, 'mix': false},
            'quality': {'audio': 'low'},
            'gifting': {'tier': 'limited'},
            'live': {
              'song_requests': {'enabled': false},
              'priority_access': false,
              'highlighted_comments': false,
            },
            'recognition': {'vip_badge': false},
            'content': {'exclusive': false, 'early_access': false},
            'content_access': 'limited',
            'content_limit_ratio': 0.3,
            'battles': {'priority': 'limited'},
          },
        },
        adsEnabled: true,
        interstitialEverySongs: 2,
        backgroundPlayEnabled: false,
        downloadsEnabled: false,
        videoDownloadsEnabled: false,
        playlistsCreateEnabled: false,
        playlistsMixEnabled: false,
        maxSkipsPerHour: 6,
        giftingTier: GiftAccessTier.limited,
        vipBadgeEnabled: false,
        highlightedCommentsEnabled: false,
        exclusiveContentEnabled: false,
        priorityLiveAccessEnabled: false,
        songRequestsEnabled: false,
        earlyAccessEnabled: false,
        contentAccess: 'limited',
        contentLimitRatio: 0.3,
        battlePriority: 'limited',
        featured: false,
        monthlyFreeCoins: 0,
        weeklyFreeCoins: 0,
        monthlyBonusCoins: 0,
      );
    }

    // Unknown plans default to the safe free profile.
    return const Entitlements(
      raw: {
        'perks': {
          'ads': {'enabled': true, 'interstitial_every_songs': 2},
          'playback': {'background_play': false, 'skips_per_hour': 6},
          'downloads': {'enabled': false},
          'playlists': {'create': false, 'mix': false},
          'quality': {'audio': 'low'},
          'gifting': {'tier': 'limited'},
          'live': {
            'song_requests': {'enabled': false},
            'priority_access': false,
            'highlighted_comments': false,
          },
          'recognition': {'vip_badge': false},
          'content': {'exclusive': false, 'early_access': false},
          'content_access': 'limited',
          'content_limit_ratio': 0.3,
          'battles': {'priority': 'limited'},
        },
      },
      adsEnabled: true,
      interstitialEverySongs: 2,
      backgroundPlayEnabled: false,
      downloadsEnabled: false,
      videoDownloadsEnabled: false,
      playlistsCreateEnabled: false,
      playlistsMixEnabled: false,
      maxSkipsPerHour: 6,
      giftingTier: GiftAccessTier.limited,
      vipBadgeEnabled: false,
      highlightedCommentsEnabled: false,
      exclusiveContentEnabled: false,
      priorityLiveAccessEnabled: false,
      songRequestsEnabled: false,
      earlyAccessEnabled: false,
      contentAccess: 'limited',
      contentLimitRatio: 0.3,
      battlePriority: 'limited',
      featured: false,
      monthlyFreeCoins: 0,
      weeklyFreeCoins: 0,
      monthlyBonusCoins: 0,
    );
  }
}
