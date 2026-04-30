import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/weafrica_colors.dart';
import '../auth/auth_actions.dart';
import '../profile/edit_profile_screen.dart';
import '../subscriptions/role_based_subscription_screen.dart';
import 'settings_controller.dart';

class ConsumerSettingsScreen extends StatefulWidget {
  const ConsumerSettingsScreen({super.key});

  @override
  State<ConsumerSettingsScreen> createState() => _ConsumerSettingsScreenState();
}

class _ConsumerSettingsScreenState extends State<ConsumerSettingsScreen> {
  final _controller = SettingsController.instance;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile Section
          _buildSectionTitle('Profile'),
          _buildSettingsTile(
            icon: Icons.person_outline,
            title: 'Edit Profile',
            subtitle: 'Update your name and photo',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),
          _buildSettingsTile(
            icon: Icons.favorite_outline,
            title: 'Liked Songs',
            subtitle: 'View your favorite tracks',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.playlist_play,
            title: 'My Playlists',
            subtitle: 'Manage your playlists',
            onTap: () {},
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Subscription'),
          _buildSettingsTile(
            icon: Icons.workspace_premium,
            title: 'Premium Subscription',
            subtitle: 'Upgrade for unlimited access',
            trailing: _buildPlanBadge('FREE'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoleBasedSubscriptionScreen()),
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Listening Preferences'),
          _buildSettingsTile(
            icon: Icons.wifi,
            title: 'Stream Quality',
            subtitle: 'WiFi only or Mobile data',
            trailing: _buildQualityBadge('Auto'),
            onTap: () => _showQualityDialog(),
          ),
          _buildSettingsTile(
            icon: Icons.download_outlined,
            title: 'Downloads',
            subtitle: 'Manage offline music',
            onTap: () {},
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Notifications'),
          _buildSwitchTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'New releases and updates',
            value: _controller.pushNotifications,
            onChanged: (v) => _controller.setPushNotifications(v),
          ),
          _buildSwitchTile(
            icon: Icons.new_releases_outlined,
            title: 'New Releases',
            subtitle: 'Get notified about new music',
            value: _controller.newReleases,
            onChanged: (v) => _controller.setNewReleases(v),
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Account'),
          _buildSettingsTile(
            icon: Icons.logout,
            title: 'Log Out',
            subtitle: 'Sign out of your account',
            iconColor: Colors.red,
            onTap: () => _confirmLogout(),
          ),
          _buildSettingsTile(
            icon: Icons.delete_outline,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            iconColor: Colors.red,
            onTap: () {},
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              'WeAfrica Music v1.0.0',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: WeAfricaColors.gold,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1530),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.white70,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1530),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white70,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: WeAfricaColors.gold,
      ),
    );
  }

  Widget _buildQualityBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WeAfricaColors.gold.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: WeAfricaColors.gold,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPlanBadge(String plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WeAfricaColors.gold.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        plan,
        style: TextStyle(
          color: WeAfricaColors.gold,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _showQualityDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1530),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stream Quality',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              _buildQualityOption('Auto', 'Adjusts based on connection'),
              _buildQualityOption('High', 'Best quality'),
              _buildQualityOption('Normal', 'Balanced'),
              _buildQualityOption('Low', 'Save data'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOption(String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      trailing: const Icon(Icons.check_circle, color: WeAfricaColors.gold),
      onTap: () => Navigator.pop(context),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1530),
        title: const Text('Log Out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedback.mediumImpact();
      await AuthActions.logout(context);
    }
  }
}