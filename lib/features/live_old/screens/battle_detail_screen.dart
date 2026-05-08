import 'package:flutter/material.dart';

/// Mode for battle detail screen.
enum BattleDetailMode { live, upcoming, ended }

/// Stub: Battle detail screen - shows details about a specific battle.
class BattleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> row;
  final BattleDetailMode mode;
  final VoidCallback? onPrimaryAction;

  const BattleDetailScreen({
    super.key,
    required this.row,
    required this.mode,
    this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final title = (row['title'] ?? 'Battle').toString();
    
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_mma, size: 64),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Mode: ${mode.name}'),
            const SizedBox(height: 24),
            if (onPrimaryAction != null)
              ElevatedButton(
                onPressed: onPrimaryAction,
                child: const Text('Join Battle'),
              )
            else
              const Text('Battle details coming soon'),
          ],
        ),
      ),
    );
  }
}