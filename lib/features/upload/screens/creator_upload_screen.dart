import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/stage_background.dart';
import '../../auth/user_role.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../models/upload_queue_item.dart';
import '../services/upload_queue_service.dart';
import '../widgets/upload_queue_indicator.dart';
import 'upload_track_screen.dart';
import 'upload_video_screen.dart';

class CreatorUploadScreen extends StatelessWidget {
  const CreatorUploadScreen({
    super.key,
    this.creatorIntent = UserRole.artist,
  });

  final UserRole creatorIntent;

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => screen,
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openTrackScreen(BuildContext context) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: creatorIntent,
      capability: CreatorCapability.uploadTrack,
    );
    if (!allowed || !context.mounted) return;

    _openScreen(
      context,
      UploadTrackScreen(creatorIntent: creatorIntent),
    );
  }

  Future<void> _openVideoScreen(BuildContext context) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: creatorIntent,
      capability: CreatorCapability.uploadVideo,
    );
    if (!allowed || !context.mounted) return;

    _openScreen(
      context,
      UploadVideoScreen(creatorIntent: creatorIntent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final studioTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.stageGold,
        secondary: AppColors.stagePurple,
      ),
    );
    final scheme = studioTheme.colorScheme;

    return Theme(
      data: studioTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: StageBackground(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 110,
                pinned: true,
                title: const Text(
                  'STUDIO',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Center(child: UploadQueueIndicator()),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WELCOME TO YOUR STUDIO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Drop tracks. Release visuals. Build your catalog. '
                          'Every upload is optimized for the stage.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textMuted, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _StatCard(label: 'TODAY', value: '0', icon: Icons.today, color: scheme.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: 'THIS WEEK', value: '0', icon: Icons.weekend, color: scheme.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: 'TOTAL', value: '0', icon: Icons.cloud_done, color: scheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'CHOOSE YOUR NEXT MOVE',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: scheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _UploadCard(
                          title: 'DROP TRACK',
                          subtitle: 'MP3, M4A, WAV, FLAC',
                          icon: Icons.audiotrack,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primary.withValues(alpha: 0.18),
                              AppColors.surface,
                            ],
                          ),
                          onTap: () => _openTrackScreen(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _UploadCard(
                          title: 'RELEASE VIDEO',
                          subtitle: 'MP4, MOV, WebM',
                          icon: Icons.videocam,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.secondary.withValues(alpha: 0.18),
                              AppColors.surface,
                            ],
                          ),
                          onTap: () => _openVideoScreen(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'RECENT UPLOADS',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: scheme.primary),
                  ),
                  const SizedBox(height: 12),
                  _RecentUploadsBox(service: UploadQueueService()),
                  const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 30, color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentUploadsBox extends StatefulWidget {
  const _RecentUploadsBox({required this.service});

  final UploadQueueService service;

  @override
  State<_RecentUploadsBox> createState() => _RecentUploadsBoxState();
}

class _RecentUploadsBoxState extends State<_RecentUploadsBox> {
  late Future<List<UploadQueueItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.loadPersisted();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UploadQueueItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text('Could not load uploads', style: TextStyle(color: AppColors.textMuted)),
            ),
          );
        }

        if (items == null || items.isEmpty) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text('No recent uploads', style: TextStyle(color: AppColors.textMuted)),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${it.mediaType.name.toUpperCase()} • ${it.stage} • ${(it.progress * 100).toStringAsFixed(0)}% • ${it.message}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
