import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/config/api_env.dart';
import '../../app/config/app_env.dart';
import '../../app/config/firebase_web_env.dart';
import '../../app/config/supabase_env.dart';
import '../../app/theme.dart';

class AppConstantsViewerScreen extends StatefulWidget {
  const AppConstantsViewerScreen({super.key});

  @override
  State<AppConstantsViewerScreen> createState() => _AppConstantsViewerScreenState();
}

class _AppConstantsViewerScreenState extends State<AppConstantsViewerScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
    setState(() {});
  }

  String _mask(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.length <= 8) return '••••';
    return '${v.substring(0, 4)}••••${v.substring(v.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final product = const bool.fromEnvironment('dart.vm.product');
    final fb = FirebaseWebEnv.tryOptions();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('App Constants'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('App Info', [
            _InfoRow('App Name', 'WeAfrica Music'),
            _InfoRow('Version', _packageInfo?.version ?? 'Loading...'),
            _InfoRow('Build Number', _packageInfo?.buildNumber ?? 'Loading...'),
            _InfoRow('Package', _packageInfo?.packageName ?? 'Loading...'),
          ]),
          const SizedBox(height: 16),
          _buildSection('Networking', [
            _InfoRow('ApiEnv.baseUrl', ApiEnv.baseUrl.isEmpty ? 'Not set' : ApiEnv.baseUrl),
            _InfoRow(
              'WEAFRICA_API_BASE_URL',
              ApiEnv.definedBaseUrl.isEmpty ? '(not defined)' : ApiEnv.definedBaseUrl,
            ),
            _InfoRow(
              'Vercel bypass token',
              AppEnv.vercelProtectionBypassToken.isEmpty ? '(not set)' : _mask(AppEnv.vercelProtectionBypassToken),
            ),
            _InfoRow(
              'PayChangu path',
              AppEnv.payChanguStartPath.isEmpty ? '(not set)' : AppEnv.payChanguStartPath,
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('Supabase', [
            _InfoRow('Supabase URL', SupabaseEnv.supabaseUrl.isEmpty ? 'Not set' : SupabaseEnv.supabaseUrl),
            _InfoRow('Project Ref', SupabaseEnv.projectRef.isEmpty ? '(unknown)' : SupabaseEnv.projectRef),
            _InfoRow('Loaded From Asset', SupabaseEnv.loadedFromAsset ? 'Yes' : 'No'),
            _InfoRow(
              'Anon Key',
              SupabaseEnv.supabaseAnonKey.isEmpty ? 'Not set' : _mask(SupabaseEnv.supabaseAnonKey),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('App Defaults', [
            _InfoRow('Default Plan', AppEnv.defaultPlanId.isEmpty ? '(not set)' : AppEnv.defaultPlanId),
            _InfoRow(
              'Default Country',
              AppEnv.defaultCountryCode.isEmpty ? '(not set)' : AppEnv.defaultCountryCode,
            ),
            _InfoRow('Test Token', AppEnv.testToken.isEmpty ? '(not set)' : _mask(AppEnv.testToken)),
          ]),
          const SizedBox(height: 16),
          _buildSection('Features', [
            _InfoRow('Debug Mode', product ? 'No' : 'Yes'),
            _InfoRow('Release Mode', product ? 'Yes' : 'No'),
            _InfoRow('Platform', Theme.of(context).platform.name),
          ]),
          const SizedBox(height: 16),
          _buildSection('Screen Sizes', [
            _InfoRow('Screen Width', '${MediaQuery.of(context).size.width} dp'),
            _InfoRow('Screen Height', '${MediaQuery.of(context).size.height} dp'),
            _InfoRow('Pixel Ratio', '${MediaQuery.of(context).devicePixelRatio}'),
            _InfoRow('Orientation', MediaQuery.of(context).orientation.name),
          ]),
          const SizedBox(height: 16),
          _buildSection('Firebase (Web)', [
            _InfoRow('Configured', fb == null ? 'No' : 'Yes'),
            if (fb != null) _InfoRow('Project ID', fb.projectId),
            if (fb != null) _InfoRow('App ID', _mask(fb.appId)),
            if (fb != null) _InfoRow('Sender ID', fb.messagingSenderId),
          ]),
          const SizedBox(height: 16),
          _buildSection('Theme', [
            _InfoRow('Theme Mode', 'Dark'),
            _InfoRow('Accent (secondary)', accent.toString()),
            _InfoRow('Background', AppColors.background.toString()),
            _InfoRow('Surface', AppColors.surface.toString()),
          ]),
          const SizedBox(height: 16),
          _buildSection('Device Info', [
            _InfoRow('Platform', 'Flutter'),
            _InfoRow('Runtime', 'Dart'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.data_usage, color: Theme.of(context).colorScheme.secondary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
