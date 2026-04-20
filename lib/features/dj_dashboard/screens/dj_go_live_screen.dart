import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../live/screens/go_live_setup_screen.dart';
import '../../auth/user_role.dart';

class DjGoLiveScreen extends StatefulWidget {
  const DjGoLiveScreen({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<DjGoLiveScreen> createState() => _DjGoLiveScreenState();
}

class _DjGoLiveScreenState extends State<DjGoLiveScreen> {
  String _userId = '';
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userId = user.uid;
        _userName = user.displayName ?? 'DJ';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) {
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text('Go Live'),
                backgroundColor: Colors.transparent,
                elevation: 0,
              )
            : null,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Go Live'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: GoLiveSetupScreen(
        role: UserRole.dj,
        hostId: _userId,
        hostName: _userName,
        initialBattleModeEnabled: false,
      ),
    );
  }
}
