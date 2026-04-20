import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'settings_controller.dart';

class CreatorNotificationsSettingsScreen extends StatefulWidget {
  const CreatorNotificationsSettingsScreen({super.key});

  @override
  State<CreatorNotificationsSettingsScreen> createState() => _CreatorNotificationsSettingsScreenState();
}

class _CreatorNotificationsSettingsScreenState extends State<CreatorNotificationsSettingsScreen> {
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
          appBar: AppBar(title: const Text('Notifications')),
          body: ListView(
            children: [
              SwitchListTile(
                value: _controller.pushNotifications,
                onChanged: (v) => _controller.setPushNotifications(v),
                title: const Text('Push notifications', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Allow push notifications', style: TextStyle(color: AppColors.textMuted)),
              ),
              SwitchListTile(
                value: _controller.newReleases,
                onChanged: _controller.pushNotifications ? (v) => _controller.setNewReleases(v) : null,
                title: const Text('New releases', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Be notified about new music', style: TextStyle(color: AppColors.textMuted)),
              ),
              SwitchListTile(
                value: _controller.favoritesUpdates,
                onChanged: _controller.pushNotifications ? (v) => _controller.setFavoritesUpdates(v) : null,
                title: const Text('Favorites updates', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Updates from artists you follow', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        );
      },
    );
  }
}
