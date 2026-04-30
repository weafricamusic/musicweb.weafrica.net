import 'package:flutter/material.dart';
import '../../../app/theme/weafrica_colors.dart';

/// Connection status indicator for live streams
/// Shows network quality, reconnection states, and readiness indicators
enum ConnectionStatus {
  connecting,
  connected,
  reconnecting,
  poorConnection,
  disconnected,
}

/// Live Readiness Card showing all system checks
/// 
/// Camera: Ready
/// Mic: Ready
/// Network: Good
/// Agora: Connected
/// Role: Artist/DJ verified
class LiveReadinessCard extends StatelessWidget {
  const LiveReadinessCard({
    super.key,
    required this.isCameraReady,
    required this.isMicReady,
    required this.networkQuality,
    required this.isAgoraConnected,
    required this.userRole,
  });

  final bool isCameraReady;
  final bool isMicReady;
  final String networkQuality; // 'Good', 'Fair', 'Poor'
  final bool isAgoraConnected;
  final String userRole; // 'Artist', 'DJ', 'Verified'

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LIVE READINESS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _ReadinessItem(
            icon: Icons.videocam,
            label: 'Camera',
            status: isCameraReady ? 'Ready' : 'Checking...',
            isReady: isCameraReady,
          ),
          _ReadinessItem(
            icon: Icons.mic,
            label: 'Microphone',
            status: isMicReady ? 'Ready' : 'Checking...',
            isReady: isMicReady,
          ),
          _ReadinessItem(
            icon: Icons.wifi,
            label: 'Network',
            status: networkQuality,
            isReady: networkQuality == 'Good',
            isWarning: networkQuality == 'Fair',
          ),
          _ReadinessItem(
            icon: Icons.cloud_done,
            label: 'Agora',
            status: isAgoraConnected ? 'Connected' : 'Connecting...',
            isReady: isAgoraConnected,
          ),
          _ReadinessItem(
            icon: Icons.verified_user,
            label: 'Role',
            status: '$userRole verified',
            isReady: true,
          ),
        ],
      ),
    );
  }
}

class _ReadinessItem extends StatelessWidget {
  const _ReadinessItem({
    required this.icon,
    required this.label,
    required this.status,
    required this.isReady,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool isReady;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    if (isReady) {
      statusColor = WeAfricaColors.success;
    } else if (isWarning) {
      statusColor = WeAfricaColors.warning;
    } else {
      statusColor = Colors.white54;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple connection status indicator for top bar
class ConnectionStatusIndicator extends StatelessWidget {
  const ConnectionStatusIndicator({
    super.key,
    required this.status,
    this.showLabel = true,
  });

  final ConnectionStatus status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case ConnectionStatus.connecting:
        color = WeAfricaColors.warning;
        icon = Icons.sync;
        label = 'Connecting...';
        break;
      case ConnectionStatus.connected:
        color = WeAfricaColors.success;
        icon = Icons.wifi;
        label = 'Live';
        break;
      case ConnectionStatus.reconnecting:
        color = WeAfricaColors.warning;
        icon = Icons.sync_problem;
        label = 'Reconnecting...';
        break;
      case ConnectionStatus.poorConnection:
        color = Colors.orange;
        icon = Icons.signal_cellular_connected_no_internet_4_bar;
        label = 'Poor Connection';
        break;
      case ConnectionStatus.disconnected:
        color = WeAfricaColors.error;
        icon = Icons.cloud_off;
        label = 'Disconnected';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reconnecting overlay with progress
class ReconnectingOverlay extends StatelessWidget {
  const ReconnectingOverlay({
    super.key,
    required this.attempt,
    this.maxAttempts = 5,
  });

  final int attempt;
  final int maxAttempts;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: WeAfricaColors.gold,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Reconnecting...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Attempt $attempt of $maxAttempts',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please check your internet connection',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty opponent state for battle waiting
class EmptyOpponentState extends StatelessWidget {
  const EmptyOpponentState({
    super.key,
    this.onInvite,
    this.onCancel,
  });

  final VoidCallback? onInvite;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline,
              size: 40,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Waiting for Opponent',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your battle link or invite an artist',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onInvite,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WeAfricaColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}