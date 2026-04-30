import 'package:flutter/material.dart';
import '../../auth/user_role.dart';
import '../../auth/user_role_store.dart';
import '../screens/battle_challenge_screen.dart';

/// Challenge Button Widget
/// 
/// Shows only for Artists and DJs when watching a live stream
/// Allows them to challenge the host to a battle
class ChallengeButton extends StatefulWidget {
  const ChallengeButton({
    super.key,
    required this.hostId,
    required this.hostName,
    required this.hostAvatar,
  });

  final String hostId;
  final String hostName;
  final String hostAvatar;

  @override
  State<ChallengeButton> createState() => _ChallengeButtonState();
}

class _ChallengeButtonState extends State<ChallengeButton> {
  UserRole _currentRole = UserRole.consumer;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await UserRoleStore.getRole();
    if (mounted) {
      setState(() => _currentRole = role);
    }
  }

  bool get _canChallenge {
    // Only Artists and DJs can challenge
    return _currentRole == UserRole.artist || _currentRole == UserRole.dj;
  }

  void _onChallengePressed() {
    if (!_canChallenge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only Artists and DJs can send challenges'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show challenge screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BattleChallengeScreen(
          targetUserId: widget.hostId,
          targetName: widget.hostName,
          targetAvatar: widget.hostAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Don't show for consumers
    if (!_canChallenge) return const SizedBox.shrink();

    return Positioned(
      bottom: 120,
      right: 16,
      child: GestureDetector(
        onTap: _onChallengePressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF4757),
                Color(0xFFFF6348),
              ],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4757).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_mma,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Challenge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}