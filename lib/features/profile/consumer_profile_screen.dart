import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';

class ConsumerProfileScreen extends StatefulWidget {
  const ConsumerProfileScreen({super.key});

  @override
  State<ConsumerProfileScreen> createState() => _ConsumerProfileScreenState();
}

class _ConsumerProfileScreenState extends State<ConsumerProfileScreen> {
  final _displayNameController = TextEditingController();
  final _photoUrlController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _displayNameController.text = (user?.displayName ?? '').trim();
    _photoUrlController.text = (user?.photoURL ?? '').trim();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to edit your profile.')),
      );
      return;
    }

    final displayName = _displayNameController.text.trim();
    final photoUrl = _photoUrlController.text.trim();

    setState(() => _saving = true);
    try {
      if (displayName != user.displayName) {
        await user.updateDisplayName(displayName.isEmpty ? null : displayName);
      }
      if (photoUrl != user.photoURL) {
        await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);
      }

      await user.reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.of(context).maybePop();
    } catch (e, st) {
      UserFacingError.log('ConsumerProfileScreen._save', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              e,
              fallback: 'Could not update profile. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    final email = user?.email ?? '';
    final avatarUrl = (user?.photoURL ?? '').trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'CONSUMER PROFILE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 35,
                  backgroundColor: AppColors.surface2,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? const Icon(Icons.person_outline, color: AppColors.textMuted, size: 40)
                      : null,
                ),
                const SizedBox(width: 16),
                
                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? 'Music Fan' : displayName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isEmpty ? 'No email' : email,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, size: 16, color: AppColors.textMuted),
                            SizedBox(width: 6),
                            Text(
                              'CONSUMER',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Profile Settings
          _buildSectionTitle('Profile Settings'),
          const SizedBox(height: 12),

          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. WeAfrica Fan',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _photoUrlController,
            decoration: const InputDecoration(
              labelText: 'Profile photo URL',
              hintText: 'https://...',
              prefixIcon: Icon(Icons.image_outlined),
            ),
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 24),

          // Consumer Features
          _buildSectionTitle('Consumer Features'),
          const SizedBox(height: 12),

          _buildFeatureCard(
            icon: Icons.favorite,
            title: 'Liked Songs',
            subtitle: 'View and manage your favorite tracks',
            onTap: () {
              // Navigate to liked songs
            },
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.download,
            title: 'Downloads',
            subtitle: 'Manage your offline music collection',
            onTap: () {
              // Navigate to downloads
            },
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.history,
            title: 'Listening History',
            subtitle: 'See what you\'ve been listening to',
            onTap: () {
              // Navigate to history
            },
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.playlist_play,
            title: 'Playlists',
            subtitle: 'Create and manage your playlists',
            onTap: () {
              // Navigate to playlists
            },
          ),

          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text(
                'SAVE CHANGES',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Consumer Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About Consumer Accounts',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Consumer accounts are for music listeners who want to enjoy '
                  'WeAfrica Music\'s vast library of songs, create playlists, and '
                  'discover new music. Unlike artist and DJ accounts, consumer '
                  'accounts do not have content creation or monetization features.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    const Text(
                      'Listen to unlimited music',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    const Text(
                      'Create and share playlists',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    const Text(
                      'Download for offline listening',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: AppColors.text,
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
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