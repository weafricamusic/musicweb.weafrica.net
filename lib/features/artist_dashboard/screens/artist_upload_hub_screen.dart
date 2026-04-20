import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../auth/user_role.dart';
import '../../subscriptions/services/creator_entitlement_gate.dart';
import '../../upload/screens/upload_track_screen.dart';
import '../../upload/screens/upload_video_screen.dart';
import '../../social/screens/photo_song_post_mockup_screen.dart';

class ArtistUploadHubScreen extends StatelessWidget {
  const ArtistUploadHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => screen,
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openSongUpload(BuildContext context) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: UserRole.artist,
      capability: CreatorCapability.uploadTrack,
    );
    if (!allowed || !context.mounted) return;

    _open(context, const UploadTrackScreen(creatorIntent: UserRole.artist));
  }

  Future<void> _openVideoUpload(BuildContext context) async {
    final allowed = await CreatorEntitlementGate.instance.ensureAllowed(
      context,
      role: UserRole.artist,
      capability: CreatorCapability.uploadVideo,
    );
    if (!allowed || !context.mounted) return;

    _open(context, const UploadVideoScreen(creatorIntent: UserRole.artist));
  }

  void _openPhotoSong(BuildContext context) {
    _open(context, const PhotoSongPostMockupScreen(role: UserRole.artist));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Upload',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose what you want to post.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          _ActionCard(
            icon: Icons.music_note_outlined,
            title: 'Upload Song',
            subtitle: 'Audio only',
            onTap: () => _openSongUpload(context),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.ondemand_video_outlined,
            title: 'Upload Video',
            subtitle: 'Music video or visualizer',
            onTap: () => _openVideoUpload(context),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.image_outlined,
            title: 'Upload Photo + Song',
            subtitle: 'Your unique post type',
            onTap: () => _openPhotoSong(context),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
