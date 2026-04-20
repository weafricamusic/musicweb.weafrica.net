import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountryService {
  CountryService._();

  static const _prefsKey = 'country_service.country_code.v1';
  static const _channel = MethodChannel('weafrica/country');

  static const String defaultCountryCode = 'MW';

  static Future<String> getCachedCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_prefsKey) ?? '').trim().toUpperCase();
    return _normalize(raw) ?? defaultCountryCode;
  }

  static Future<String> detectCountryCodeBestEffort() async {
    // Primary: native telephony (Android). iOS will likely return locale.
    try {
      final res = await _channel.invokeMethod<String>('getCountryCode');
      final normalized = _normalize(res);
      if (normalized != null) return normalized;
    } catch (_) {
      // ignore and fall back
    }

    // Secondary: platform locale region.
    try {
      final locale = PlatformDispatcher.instance.locale;
      final region = locale.countryCode;
      final normalized = _normalize(region);
      if (normalized != null) return normalized;
    } catch (_) {
      // ignore
    }

    return defaultCountryCode;
  }

  static Future<String> ensureCountryCodeCached() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_prefsKey) ?? '').trim();
    final normalizedExisting = _normalize(existing);
    if (normalizedExisting != null) return normalizedExisting;

    final detected = await detectCountryCodeBestEffort();
    await prefs.setString(_prefsKey, detected);
    return detected;
  }

  static Future<void> setCountryCode(String countryCode) async {
    final normalized = _normalize(countryCode) ?? defaultCountryCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
  }

  static String? _normalize(String? input) {
    final raw = (input ?? '').trim().toUpperCase();
    if (raw.isEmpty) return null;

    // Accept ISO-3166 alpha-2 only.
    final ok = RegExp(r'^[A-Z]{2}$').hasMatch(raw);
    if (!ok) return null;
    return raw;
  }

  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoidprint
      print('CountryService: $message');
    }
  }
}
