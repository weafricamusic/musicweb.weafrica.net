import 'package:flutter/material.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../models/beat_model.dart';
import '../services/beat_service.dart';

class BeatSelectionWidget extends StatefulWidget {
  const BeatSelectionWidget({
    super.key,
    required this.onBeatSelected,
    this.initialBeatId,
  });

  final Function(BeatModel?) onBeatSelected;
  final String? initialBeatId;

  @override
  State<BeatSelectionWidget> createState() => _BeatSelectionWidgetState();
}

class _BeatSelectionWidgetState extends State<BeatSelectionWidget> {
  final BeatService _beatService = BeatService();
  List<BeatModel> _beats = [];
  BeatModel? _selectedBeat;
  bool _isLoading = true;
  String? _error;

  static const Duration _loadTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _loadBeats();
  }

  Future<void> _loadBeats() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }

      final beats = await _beatService.getAvailableBeats().timeout(_loadTimeout);

      if (!mounted) return;
      setState(() {
        _beats = beats;

        if (widget.initialBeatId != null && _beats.isNotEmpty) {
          _selectedBeat = _beats.firstWhere(
            (b) => b.id == widget.initialBeatId,
            orElse: () => _beats.first,
          );
          widget.onBeatSelected(_selectedBeat);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Colors.black.withValues(alpha: 0.22);
    final borderColor = Colors.white.withValues(alpha: 0.18);
    final goldAlpha = WeAfricaColors.gold.withValues(alpha: 0.2);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: WeAfricaColors.gold, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'SELECT YOUR BEAT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_selectedBeat != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: goldAlpha,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: WeAfricaColors.gold, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_selectedBeat!.duration}s',
                          style: const TextStyle(color: WeAfricaColors.gold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: WeAfricaColors.gold)),
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 32),
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _loadBeats,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _beats.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No beats available', style: TextStyle(color: Colors.white70)),
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _beats.length,
                          itemBuilder: (context, index) {
                            final beat = _beats[index];
                            final isSelected = _selectedBeat?.id == beat.id;
                            return _BeatCard(
                              beat: beat,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _selectedBeat = isSelected ? null : beat;
                                });
                                widget.onBeatSelected(_selectedBeat);
                              },
                            );
                          },
                        ),
        ],
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
    final gradientColors = isSelected
        ? [WeAfricaColors.gold, WeAfricaColors.goldDark]
        : [Colors.grey[900]!, Colors.grey[850]!];

    final darkOverlay = Colors.black.withValues(alpha: 0.2);
    final lightOverlay = Colors.white.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: WeAfricaColors.gold, width: 2) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 32,
              color: isSelected ? Colors.black : WeAfricaColors.gold,
            ),
            const SizedBox(height: 8),
            Text(
              beat.name,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (beat.bpm > 0)
              Text(
                '${beat.bpm} BPM',
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.white70,
                  fontSize: 10,
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? darkOverlay : lightOverlay,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${beat.duration}s',
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}