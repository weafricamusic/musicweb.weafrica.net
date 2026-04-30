import 'package:flutter/material.dart';

import '../../../../app/theme/weafrica_colors.dart';
import '../../models/stream_challenge.dart';

class ChallengeBanner extends StatelessWidget {
  const ChallengeBanner({
    super.key,
    required this.challenge,
    required this.onAccept,
    required this.onDismiss,
    this.accepting = false,
  });

  final StreamChallenge challenge;
  final Future<void> Function() onAccept;
  final VoidCallback onDismiss;
  final bool accepting;

  /// Determine the display label of the challenger
  String _label() {
    final handle = challenge.challenger?.username.trim();
    final display = challenge.challenger?.displayName.trim();

    if (handle != null && handle.isNotEmpty) return '@$handle';
    if (display != null && display.isNotEmpty) return display;
    return challenge.challengerId;
  }

  @override
  Widget build(BuildContext context) {
    final who = _label();
    final msg = (challenge.message ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sports_mma, color: WeAfricaColors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Battle challenge from $who',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (msg.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    msg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: accepting ? null : onDismiss,
            child: Text(
              accepting ? '...' : 'Later',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: accepting ? null : () async => onAccept(),
            style: ElevatedButton.styleFrom(
              backgroundColor: WeAfricaColors.gold,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              accepting ? '...' : 'Accept',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}