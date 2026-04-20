import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme.dart';

class AboutWeAfricaMusicPage extends StatelessWidget {
  const AboutWeAfricaMusicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About WeAfrica Music')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/launcher_icon.png',
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.music_note),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WeAfrica Music',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Listen, discover, and support African music.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final info = snap.data;
              final version = info == null ? '…' : '${info.version} (${info.buildNumber})';
              final package = info?.packageName ?? '…';

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: const Text('Version'),
                      subtitle: Text(version, style: TextStyle(color: AppColors.textMuted)),
                    ),
                    Divider(height: 1, color: AppColors.border),
                    ListTile(
                      dense: true,
                      title: const Text('Package'),
                      subtitle: Text(package, style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open-source licenses'),
                  onTap: () => showLicensePage(context: context, applicationName: 'WeAfrica Music'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
