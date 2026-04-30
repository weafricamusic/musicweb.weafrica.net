import 'package:flutter/material.dart';

class BattleInvitePopup extends StatelessWidget {
  const BattleInvitePopup({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Battle Invite"),
      content: const Text("New battle invite received."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Decline"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Accept"),
        ),
      ],
    );
  }
}
