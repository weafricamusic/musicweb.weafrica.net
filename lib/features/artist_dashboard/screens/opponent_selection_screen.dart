import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../auth/user_role.dart';
import '../../live/services/battle_service.dart';
import 'waiting_for_opponent_screen.dart';

class OpponentSelectionScreen extends StatefulWidget {
  const OpponentSelectionScreen({
    super.key,
    required this.battleId,
    required this.channelId,
    required this.battleTitle,
    required this.durationSeconds,
    required this.coinGoal,
    required this.hostId,
    required this.hostName,
    required this.hostRole,
    this.beatId,
    this.beatName,
  });

  final String battleId;
  final String channelId;
  final String battleTitle;
  final int durationSeconds;
  final int coinGoal;
  final String hostId;
  final String hostName;
  final UserRole hostRole;
  final String? beatId;
  final String? beatName;

  @override
  State<OpponentSelectionScreen> createState() => _OpponentSelectionScreenState();
}

class _OpponentSelectionScreenState extends State<OpponentSelectionScreen> {
  List<Map<String, dynamic>> _potentialOpponents = const <Map<String, dynamic>>[];
  bool _isLoading = true;
  String? _selectedOpponentId;

  @override
  void initState() {
    super.initState();
    _loadPotentialOpponents();
  }

  Future<void> _loadPotentialOpponents() async {
    setState(() => _isLoading = true);

    try {
      final opponents = await BattleService().getPotentialOpponents(
        excludeUserId: widget.hostId,
        role: widget.hostRole,
      );

      if (!mounted) return;
      setState(() {
        _potentialOpponents = opponents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading opponents: $e'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
    }
  }

  Future<void> _sendInvite() async {
    final selected = (_selectedOpponentId ?? '').trim();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an opponent'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (kDebugMode) {
        debugPrint('📨 SEND BATTLE INVITE tapped: battleId=${widget.battleId} to=$selected from=${widget.hostId}');
      }
      await BattleService().sendBattleInvite(
        battleId: widget.battleId,
        channelId: widget.channelId,
        fromUserId: widget.hostId,
        fromUserName: widget.hostName,
        toUserId: selected,
        battleTitle: widget.battleTitle,
        durationSeconds: widget.durationSeconds,
        coinGoal: widget.coinGoal,
      );

      if (kDebugMode) {
        debugPrint('✅ Invite API call completed: battleId=${widget.battleId} to=$selected');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WaitingForOpponentScreen(
            battleId: widget.battleId,
            channelId: widget.channelId,
            battleTitle: widget.battleTitle,
            opponentId: selected,
            hostId: widget.hostId,
            hostName: widget.hostName,
            beatId: widget.beatId,
            beatName: widget.beatName,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Invite API call failed: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending invite: $e'),
          backgroundColor: WeAfricaColors.error,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      appBar: AppBar(
        title: const Text('Choose Opponent'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: WeAfricaColors.gold),
            )
          : _potentialOpponents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No opponents available',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back later for other artists',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadPotentialOpponents,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WeAfricaColors.gold,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _potentialOpponents.length,
                        itemBuilder: (context, index) {
                          final opponent = _potentialOpponents[index];
                          final id = (opponent['id'] ?? '').toString().trim();
                          final name = (opponent['name'] ?? 'Artist').toString().trim();
                          final category = (opponent['category'] ?? 'Artist').toString().trim();
                          final isSelected = _selectedOpponentId == id;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedOpponentId = id;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? WeAfricaColors.goldWithOpacity(0.15)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? WeAfricaColors.gold
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: WeAfricaColors.goldWithOpacity(0.2),
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: WeAfricaColors.gold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isNotEmpty ? name : 'Artist',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          category.isNotEmpty ? category : 'Artist',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: WeAfricaColors.gold,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.black,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _sendInvite,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WeAfricaColors.gold,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'SEND BATTLE INVITE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
