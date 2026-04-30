import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../models/beat_model.dart';
import '../services/beat_service.dart';
import '../services/battle_service.dart';
import '../services/live_economy_api.dart';

class BattleChallengeScreen extends StatefulWidget {
  const BattleChallengeScreen({
    super.key,
    required this.targetUserId,
    required this.targetName,
    required this.targetAvatar,
  });

  final String targetUserId;
  final String targetName;
  final String targetAvatar;

  @override
  State<BattleChallengeScreen> createState() => _BattleChallengeScreenState();
}

class _BattleChallengeScreenState extends State<BattleChallengeScreen> {
  final BeatService _beatService = BeatService();
  final BattleService _battleService = BattleService();
  final LiveEconomyApi _economyApi = LiveEconomyApi();
  
  List<BeatModel> _availableBeats = [];
  BeatModel? _selectedBeat;
  int _betAmount = 1000;
  int? _coinBalance;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  Timer? _previewTimer;
  int _selectionSecondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _loadBeats();
    _startPreviewCountdown();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBeats() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _beatService.getAvailableBeats(),
        _economyApi.fetchMyCoinBalance(),
      ]);

      final beats = results[0] as List<BeatModel>;
      final balance = results[1] as int?;
      setState(() {
        _availableBeats = beats;
        _selectedBeat = beats.isNotEmpty ? beats.first : null;
        _coinBalance = balance;
        _isLoading = false;
        if (balance != null && balance > 0 && _betAmount > balance) {
          _betAmount = _normalizeBet(balance);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendChallenge() async {
    if (_selectedBeat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a beat first')),
      );
      return;
    }

    final balance = _coinBalance;
    if (balance != null && balance > 0 && _betAmount > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have enough coins for that bet.'),
          backgroundColor: WeAfricaColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final challenge = await _battleService.sendChallenge(
        targetUserId: widget.targetUserId,
        beatId: _selectedBeat!.id,
        betAmount: _betAmount,
        beatName: _selectedBeat!.name,
        beatGenre: _selectedBeat!.genre,
        beatDuration: _selectedBeat!.duration,
      );
      
      if (mounted) {
        Navigator.pop(context, challenge);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challenge sent to ${widget.targetName}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: WeAfricaColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startPreviewCountdown() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_selectionSecondsLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _selectionSecondsLeft -= 1);
    });
  }

  int _normalizeBet(int value) {
    if (value <= 0) return 100;
    final rounded = (value ~/ 100) * 100;
    if (rounded < 100) return 100;
    if (rounded > 10000) return 10000;
    return rounded;
  }

  void _setBetAmount(int value) {
    setState(() {
      _betAmount = _normalizeBet(value);
    });
  }

  String _formatSelectionClock() {
    final minutes = (_selectionSecondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_selectionSecondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  ImageProvider<Object>? _targetAvatarImage() {
    final avatar = widget.targetAvatar.trim();
    if (avatar.isEmpty) return null;
    return NetworkImage(avatar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Battle Challenge'),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold))
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadBeats,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Opponent info
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: _targetAvatarImage(),
                child: widget.targetAvatar.trim().isEmpty
                    ? Text(widget.targetName.trim().isEmpty ? '?' : widget.targetName.trim()[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vs ${widget.targetName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose your beat and stake coins',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _ReactionChip(emoji: '❤️', label: 'Love'),
                        _ReactionChip(emoji: '👏', label: 'Claps'),
                        _ReactionChip(emoji: '😍', label: 'Hype'),
                        _ReactionChip(emoji: '😂', label: 'Funny'),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: WeAfricaColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on,
                        color: WeAfricaColors.gold, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_coinBalance ?? '--'}',
                      style: const TextStyle(color: WeAfricaColors.gold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: WeAfricaColors.gold),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Pick a beat before the preview timer runs out',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  _formatSelectionClock(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bet amount selector
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bet Amount',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_betAmount coins',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() {
                          if (_betAmount > 100) _betAmount -= 100;
                        }),
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          final max = _coinBalance == null ? 10000 : (_coinBalance! < 10000 ? _coinBalance! : 10000);
                          if (_betAmount < max) _betAmount += 100;
                        }),
                        icon: const Icon(Icons.add_circle_outline,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _BetChip(amount: 500, selected: _betAmount == 500, onTap: () => _setBetAmount(500)),
                  _BetChip(amount: 1000, selected: _betAmount == 1000, onTap: () => _setBetAmount(1000)),
                  _BetChip(amount: 5000, selected: _betAmount == 5000, onTap: () => _setBetAmount(5000)),
                  _BetChip(amount: 10000, selected: _betAmount == 10000, onTap: () => _setBetAmount(10000)),
                ],
              ),
            ],
          ),
        ),

        // Beat selection
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Text(
                  'Select Your Beat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _availableBeats.length,
                  itemBuilder: (context, index) {
                    final beat = _availableBeats[index];
                    final isSelected = _selectedBeat?.id == beat.id;
                    return _BeatCard(
                      beat: beat,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedBeat = beat),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Send challenge button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _isSending ? null : _sendChallenge,
            style: ElevatedButton.styleFrom(
              backgroundColor: WeAfricaColors.gold,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'SEND CHALLENGE',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _BetChip extends StatelessWidget {
  const _BetChip({required this.amount, required this.onTap, required this.selected});

  final int amount;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? WeAfricaColors.gold.withValues(alpha: 0.18) : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: WeAfricaColors.gold) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, size: 14, color: WeAfricaColors.gold),
            const SizedBox(width: 4),
            Text(
              '$amount',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatCard extends StatelessWidget {
  const _BeatCard({
    required this.beat,
    required this.isSelected,
    required this.onTap,
  });

  final BeatModel beat;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [WeAfricaColors.gold, WeAfricaColors.goldDark]
                : [Colors.grey[900]!, Colors.grey[850]!],
          ),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: WeAfricaColors.gold, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 40,
              color: isSelected ? Colors.black : WeAfricaColors.gold,
            ),
            const SizedBox(height: 8),
            Text(
              beat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              beat.genre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.black87 : Colors.white70,
                fontSize: 12,
              ),
            ),
            if (beat.duration > 0)
              Text(
                '${beat.duration}s • ${beat.bpm} BPM',
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.white70,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$emoji $label',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
