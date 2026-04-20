enum AudioQuality {
  low,
  normal,
  high,
}

enum AppThemeMode {
  system,
  light,
  dark,
}

enum AppLanguage {
  english,
  french,
  portuguese,
  swahili,
}

extension AudioQualityLabel on AudioQuality {
  String get label {
    switch (this) {
      case AudioQuality.low:
        return 'Low';
      case AudioQuality.normal:
        return 'Normal';
      case AudioQuality.high:
        return 'High';
    }
  }
}

extension AppThemeModeLabel on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.system:
        return 'System';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }
}

extension AppLanguageLabel on AppLanguage {
  String get label {
    switch (this) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.french:
        return 'French';
      case AppLanguage.portuguese:
        return 'Portuguese';
      case AppLanguage.swahili:
        return 'Swahili';
    }
  }
}
