import 'package:flutter/material.dart';

class GoLiveSetupScreen extends StatelessWidget {
  final dynamic role;
  final String? hostId;
  final String? hostName;

  const GoLiveSetupScreen({super.key, this.role, this.hostId, this.hostName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Go Live")),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Start Live (Disabled)"),
        ),
      ),
    );
  }
}
