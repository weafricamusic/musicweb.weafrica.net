import 'package:flutter/material.dart';
import '../../../app/theme/weafrica_colors.dart';

class SoloLiveStreamScreen extends StatefulWidget {
  const SoloLiveStreamScreen({
    super.key,
    required this.sessionId,
    required this.channelId,
    required this.token,
    required this.title,
    required this.hostName,
  });

  final String sessionId;
  final String channelId;
  final String token;
  final String title;
  final String hostName;

  @override
  State<SoloLiveStreamScreen> createState() => _SoloLiveStreamScreenState();
}

class _SoloLiveStreamScreenState extends State<SoloLiveStreamScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: WeAfricaColors.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic,
                size: 50,
                color: WeAfricaColors.gold,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '🎤 ${widget.hostName} is live!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Live: ${widget.title}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: WeAfricaColors.gold,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Live stream in progress',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Channel ID: ${widget.channelId.substring(0, 12)}...',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('End Live'),
            ),
          ],
        ),
      ),
    );
  }
}