import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AdMobFormat {
  banner,
  interstitial,
  rewarded,
  native,
}

extension AdMobFormatValue on AdMobFormat {
  String get value {
    switch (this) {
      case AdMobFormat.banner:
        return 'banner';
      case AdMobFormat.interstitial:
        return 'interstitial';
      case AdMobFormat.rewarded:
        return 'rewarded';
      case AdMobFormat.native:
        return 'native';
    }
  }
}

class AdMobUnitResolver {
  AdMobUnitResolver._();

  static final AdMobUnitResolver instance = AdMobUnitResolver._();

  final Map<String, String> _cache = {};

  bool get _supportsAdsPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  String get _platform {
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  Future<String?> resolve({required AdMobFormat format, required String placement, String? country}) async {
    if (!_supportsAdsPlatform) return null;

    final key = '$_platform|${format.value}|${placement.trim().toLowerCase()}|${(country ?? '').trim().toUpperCase()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final sb = Supabase.instance.client;

    Future<String?> query({String? countryCode}) async {
      final cc = (countryCode ?? '').trim().toUpperCase();

      var q = sb
          .from('ads')
          .select()
          .eq('is_active', true)
          .eq('format', format.value)
          .eq('platform', _platform)
          .eq('placement', placement.trim().toLowerCase());
      if (cc.isNotEmpty) {
        q = q.eq('country', cc);
      }

      final limited = q.limit(1);

      try {
        final row = await limited.maybeSingle();
        if (row == null) return null;

        final map = (row as Map).map((k, v) => MapEntry(k.toString(), v));
        final id = (map['ad_unit_id'] ?? '').toString().trim();
        return id.isEmpty ? null : id;
      } catch (_) {
        return null;
      }
    }

    final byCountry = await query(countryCode: country);
    if (byCountry != null) {
      _cache[key] = byCountry;
      return byCountry;
    }

    final generic = await query(countryCode: null);
    if (generic != null) {
      _cache[key] = generic;
      return generic;
    }

    return null;
  }
}
