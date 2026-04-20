import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../artist_dashboard/services/artist_dashboard_settings_service.dart';

class CreatorPrivacySecurityScreen extends StatefulWidget {
  const CreatorPrivacySecurityScreen({super.key});

  @override
  State<CreatorPrivacySecurityScreen> createState() => _CreatorPrivacySecurityScreenState();
}

class _CreatorPrivacySecurityScreenState extends State<CreatorPrivacySecurityScreen> {
  bool _exporting = false;

  Future<void> _exportData() async {
    if (_exporting) return;

    setState(() => _exporting = true);

    try {
      final data = await const ArtistDashboardSettingsService().exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: pretty));

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Export copied to clipboard.')));
    } catch (e, st) {
      UserFacingError.log('CreatorPrivacySecurityScreen._exportData', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Export failed. Please try again.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & security')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.file_download_outlined, color: cs.secondary),
            title: const Text('Export my data', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Copy your profile data as JSON', style: TextStyle(color: AppColors.textMuted)),
            trailing: _exporting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: _exporting ? null : _exportData,
          ),
        ],
      ),
    );
  }
}
