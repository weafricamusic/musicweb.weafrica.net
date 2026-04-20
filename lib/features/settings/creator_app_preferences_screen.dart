import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'settings_controller.dart';
import 'settings_models.dart';

class CreatorAppPreferencesScreen extends StatefulWidget {
  const CreatorAppPreferencesScreen({super.key});

  @override
  State<CreatorAppPreferencesScreen> createState() => _CreatorAppPreferencesScreenState();
}

class _CreatorAppPreferencesScreenState extends State<CreatorAppPreferencesScreen> {
  final _controller = SettingsController.instance;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('App preferences')),
          body: ListView(
            children: [
              SwitchListTile(
                value: _controller.autoPlay,
                onChanged: (v) => _controller.setAutoPlay(v),
                title: const Text('Autoplay', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Automatically play the next track', style: TextStyle(color: AppColors.textMuted)),
              ),
              SwitchListTile(
                value: _controller.normalizeVolume,
                onChanged: (v) => _controller.setNormalizeVolume(v),
                title: const Text('Normalize volume', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Keep volume consistent across songs', style: TextStyle(color: AppColors.textMuted)),
              ),
              SwitchListTile(
                value: _controller.wifiOnly,
                onChanged: (v) => _controller.setWifiOnly(v),
                title: const Text('Wi‑Fi only', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Download on Wi‑Fi only', style: TextStyle(color: AppColors.textMuted)),
              ),
              SwitchListTile(
                value: _controller.explicitContent,
                onChanged: (v) => _controller.setExplicitContent(v),
                title: const Text('Explicit content', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Allow explicit tracks', style: TextStyle(color: AppColors.textMuted)),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Audio quality', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Streaming & downloads', style: TextStyle(color: AppColors.textMuted)),
                trailing: _EnumDropdown<AudioQuality>(
                  value: _controller.audioQuality,
                  values: AudioQuality.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) => _controller.setAudioQuality(v),
                ),
              ),
              ListTile(
                title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('System / Light / Dark', style: TextStyle(color: AppColors.textMuted)),
                trailing: _EnumDropdown<AppThemeMode>(
                  value: _controller.themeMode,
                  values: AppThemeMode.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) => _controller.setThemeMode(v),
                ),
              ),
              ListTile(
                title: const Text('Language', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('App language', style: TextStyle(color: AppColors.textMuted)),
                trailing: _EnumDropdown<AppLanguage>(
                  value: _controller.language,
                  values: AppLanguage.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) => _controller.setLanguage(v),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EnumDropdown<T> extends StatelessWidget {
  const _EnumDropdown({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T v) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800);

    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: values
            .map(
              (v) => DropdownMenuItem<T>(
                value: v,
                child: Text(labelOf(v), style: textStyle),
              ),
            )
            .toList(growable: false),
        onChanged: (v) {
          if (v == null) return;
          onChanged(v);
        },
      ),
    );
  }
}
