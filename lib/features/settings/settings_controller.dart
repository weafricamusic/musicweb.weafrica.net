import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_models.dart';

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  static const _kAutoPlay = 'settings.autoplay';
  static const _kNormalizeVolume = 'settings.normalizeVolume';
  static const _kWifiOnly = 'settings.wifiOnly';
  static const _kExplicitContent = 'settings.explicitContent';

  static const _kAudioQuality = 'settings.audioQuality';
  static const _kThemeMode = 'settings.themeMode';
  static const _kLanguage = 'settings.language';

  static const _kPushNotifications = 'settings.pushNotifications';
  static const _kNewReleases = 'settings.newReleases';
  static const _kFavoritesUpdates = 'settings.favoritesUpdates';

  SharedPreferences? _prefs;
  bool _loaded = false;

  bool get loaded => _loaded;

  bool autoPlay = true;
  bool normalizeVolume = false;
  bool wifiOnly = true;
  bool explicitContent = false;

  AudioQuality audioQuality = AudioQuality.normal;
  AppThemeMode themeMode = AppThemeMode.system;
  AppLanguage language = AppLanguage.english;

  bool pushNotifications = true;
  bool newReleases = true;
  bool favoritesUpdates = true;

  /// Call once during app start.
  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();

    final p = _prefs!;
    autoPlay = p.getBool(_kAutoPlay) ?? autoPlay;
    normalizeVolume = p.getBool(_kNormalizeVolume) ?? normalizeVolume;
    wifiOnly = p.getBool(_kWifiOnly) ?? wifiOnly;
    explicitContent = p.getBool(_kExplicitContent) ?? explicitContent;

    audioQuality = _readEnum(p.getString(_kAudioQuality), AudioQuality.values, audioQuality);
    themeMode = _readEnum(p.getString(_kThemeMode), AppThemeMode.values, themeMode);
    language = _readEnum(p.getString(_kLanguage), AppLanguage.values, language);

    pushNotifications = p.getBool(_kPushNotifications) ?? pushNotifications;
    newReleases = p.getBool(_kNewReleases) ?? newReleases;
    favoritesUpdates = p.getBool(_kFavoritesUpdates) ?? favoritesUpdates;

    _loaded = true;
    notifyListeners();
  }

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> setAutoPlay(bool value) => _setBool(_kAutoPlay, value, (v) => autoPlay = v);
  Future<void> setNormalizeVolume(bool value) =>
      _setBool(_kNormalizeVolume, value, (v) => normalizeVolume = v);
  Future<void> setWifiOnly(bool value) => _setBool(_kWifiOnly, value, (v) => wifiOnly = v);
  Future<void> setExplicitContent(bool value) =>
      _setBool(_kExplicitContent, value, (v) => explicitContent = v);

  Future<void> setPushNotifications(bool value) =>
      _setBool(_kPushNotifications, value, (v) => pushNotifications = v);
  Future<void> setNewReleases(bool value) => _setBool(_kNewReleases, value, (v) => newReleases = v);
  Future<void> setFavoritesUpdates(bool value) =>
      _setBool(_kFavoritesUpdates, value, (v) => favoritesUpdates = v);

  Future<void> setAudioQuality(AudioQuality value) =>
      _setEnum(_kAudioQuality, value, (v) => audioQuality = v);
  Future<void> setThemeMode(AppThemeMode value) => _setEnum(_kThemeMode, value, (v) => themeMode = v);
  Future<void> setLanguage(AppLanguage value) => _setEnum(_kLanguage, value, (v) => language = v);

  Future<void> _setBool(String key, bool value, void Function(bool) assign) async {
    assign(value);
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    await p.setBool(key, value);
  }

  Future<void> _setEnum<T extends Enum>(String key, T value, void Function(T) assign) async {
    assign(value);
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    await p.setString(key, value.name);
  }

  T _readEnum<T extends Enum>(String? raw, List<T> values, T fallback) {
    if (raw == null || raw.isEmpty) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }
}
