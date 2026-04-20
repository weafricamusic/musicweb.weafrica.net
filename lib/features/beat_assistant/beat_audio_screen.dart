import 'package:flutter/material.dart';

import '../beats/screens/beat_studio_screen.dart';
import '../auth/user_role.dart';

class BeatAudioScreen extends StatelessWidget {
  const BeatAudioScreen({
    super.key,
    required this.role,
    this.openLibrary = false,
  });

  final UserRole role;
  final bool openLibrary;

  @override
  Widget build(BuildContext context) {
    return BeatStudioScreen(role: role, openLibrary: openLibrary);
  }
}
