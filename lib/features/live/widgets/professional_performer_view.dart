import 'package:flutter/material.dart';

class ProfessionalPerformerView extends StatefulWidget {
  const ProfessionalPerformerView({
    super.key,
    required this.artistName,
    required this.opponentName,
    required this.isMyTurn,
    required this.timeRemaining,
    required this.viewerCount,
    this.beatName,
    this.isMicActive = true,
    this.opponentIsActive = false,
    this.round = 1,
  });

  final String artistName;
  final String opponentName;
  final bool isMyTurn;
  final int timeRemaining;
  final int viewerCount;
  final String? beatName;
  final bool isMicActive;
  final bool opponentIsActive;
  final int round;

  @override
  State<ProfessionalPerformerView> createState() =>
      _ProfessionalPerformerViewState();
}

class _ProfessionalPerformerViewState
    extends State<ProfessionalPerformerView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    if (widget.isMyTurn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ProfessionalPerformerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isMyTurn) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Color _getTimerColor() {
    if (widget.timeRemaining <= 5) {
      return Colors.red;
    } else if (widget.timeRemaining <= 10) {
      return Colors.orange;
    } else {
      return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            /// 🔝 TOP BAR
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mic,
                          size: 16,
                          color: widget.isMicActive
                              ? Colors.greenAccent
                              : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.artistName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.red),
                        SizedBox(width: 6),
                        Text('LIVE',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            /// 🎤 MAIN STAGE
            Expanded(
              child: Center(
                child: ScaleTransition(
                  scale: _pulseController,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      /// ROUND
                      Text(
                        'ROUND ${widget.round}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (widget.isMyTurn) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade700,
                                Colors.green.shade900
                              ],
                            ),
                            borderRadius: BorderRadius.circular(60),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.greenAccent.withValues(alpha: 0.7),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Text(
                                '🎤 YOUR TURN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 16),

                              /// TIMER
                              Text(
                                _formatTime(widget.timeRemaining),
                                style: TextStyle(
                                  color: _getTimerColor(),
                                  fontSize: 56,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),

                              const SizedBox(height: 8),
                              const Text(
                                'remaining',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(60),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'WAITING',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            /// 🔻 BOTTOM INFO
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                border: const Border(top: BorderSide(color: Colors.white24)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.opponentIsActive
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.opponentIsActive
                            ? '🔥 OPPONENT PERFORMING'
                            : '⏳ OPPONENT WAITING',
                        style: TextStyle(
                          color: widget.opponentIsActive
                              ? Colors.green
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    widget.opponentName,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 16),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility,
                          color: Colors.white54, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.viewerCount} watching',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),

                  if (widget.beatName != null &&
                      widget.beatName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '🎵 ${widget.beatName}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}