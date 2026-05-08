import 'package:flutter/material.dart';

class ProfessionalBattleScreen extends StatefulWidget {
  final String sessionId;
  final String liveId;
  final String battleId;
  final String competitor1Id;
  final String competitor2Id;
  final String competitor1Name;
  final String competitor2Name;
  final String competitor1Type;
  final String competitor2Type;
  final int durationSeconds;
  final String currentUserId;
  final String currentUserName;
  final String channelId;
  final String token;
  final int agoraUid;
  final String? competitor2AvatarUrl;
  final bool autoPromptInviteOnStart;
  final String? initialBeatId;
  final String? initialBeatName;

  const ProfessionalBattleScreen({
    super.key,
    required this.sessionId,
    required this.liveId,
    required this.battleId,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.durationSeconds,
    required this.currentUserId,
    required this.currentUserName,
    required this.channelId,
    required this.token,
    required this.agoraUid,
    this.competitor2AvatarUrl,
    this.autoPromptInviteOnStart = false,
    this.initialBeatId,
    this.initialBeatName,
  });

  @override
  State<ProfessionalBattleScreen> createState() => _ProfessionalBattleScreenState();
}

class _ProfessionalBattleScreenState extends State<ProfessionalBattleScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Battle: ${widget.competitor1Name} vs ${widget.competitor2Name}'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_mma, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            Text(
              '${widget.competitor1Name} vs ${widget.competitor2Name}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'Battle Room: ${widget.channelId}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 40),
            const Text(
              'Professional battle interface coming soon',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Exit Battle'),
            ),
          ],
        ),
      ),
    );
  }
}
