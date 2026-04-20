// lib/features/live/screens/battle_lobby_screen.dart
import 'package:flutter/material.dart';

class BattleLobbyScreen extends StatelessWidget {
  const BattleLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Get battleId and inviteId from route arguments if needed
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final battleId = args?['battleId'] as String? ?? 'Loading...';
    final inviteId = args?['inviteId'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF07150B),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated battle icon
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2F9B57).withValues(alpha: 0.2),
                            const Color(0xFF2F9B57).withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.sports_mma,
                        color: Color(0xFF2F9B57),
                        size: 80,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              
              // Loading indicator
              const CircularProgressIndicator(
                color: Color(0xFF2F9B57),
                strokeWidth: 3,
              ),
              const SizedBox(height: 32),
              
              // Status text
              const Text(
                'Preparing Battle Arena...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Battle info card
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E2414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF2F9B57).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      color: Color(0xFF2F9B57),
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Battle ID: $battleId',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Waiting for opponent to confirm...',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              
              // Cancel button
              ElevatedButton.icon(
                onPressed: () {
                  _cancelBattle(context);
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel Battle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cancelBattle(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0E2414),
        title: const Text('Cancel Battle?'),
        content: const Text(
          'Are you sure you want to cancel this battle?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('No', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              Navigator.pop(context); // Go back
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
