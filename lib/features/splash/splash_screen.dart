import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../app/constants/weafrica_power_voice.dart';
import '../auth/auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.statusText,
  });

  final String? statusText;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFF2D572);
  static const Color _stageBlack = Color(0xFF050508);

  int _alpha(double opacity) => (opacity * 255).round().clamp(0, 255).toInt();

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _glowPulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    );

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _glowPulse = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _stageBlack,
      body: Stack(
        children: [
          // Stage background with gradient
          _StageBackground(),

          // Center content
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo with gold glow
                    AnimatedBuilder(
                      animation: _glowPulse,
                      builder: (context, child) {
                        return Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _gold.withAlpha(_alpha(0.3 * _glowPulse.value)),
                                blurRadius: 40 * _glowPulse.value,
                                spreadRadius: 10 * _glowPulse.value,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_gold, _goldLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withAlpha(77),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.album,
                          color: Colors.black,
                          size: 50,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Brand name with gold gradient
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [_gold, _goldLight],
                      ).createShader(bounds),
                      child: const Text(
                        'WEAFRICA',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Subtitle
                    const Text(
                      WeAfricaPowerVoice.entryLine1,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      WeAfricaPowerVoice.entryLine2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Tagline with gold dot
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Discover Africa's sound",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom loading indicator
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((widget.statusText ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          widget.statusText!.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Opacity(
                          opacity: 0.5 + (_controller.value * 0.3),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: CustomPaint(
                              painter: _StageLoaderPainter(
                                progress: _controller.value,
                                color: _gold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Stage background with theatrical gradient
class _StageBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.2, -0.2),
          radius: 1.2,
          colors: [
            const Color(0xFF1A1A28), // Deep indigo
            const Color(0xFF0A0A14), // Darker indigo
            Colors.black,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Stage lights (top)
          Positioned(
            top: -100,
            left: -50,
            right: -50,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.8,
                  colors: [
                    const Color(0xFFD4AF37).withAlpha(38),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Stage lights (bottom)
          Positioned(
            bottom: -100,
            left: -50,
            right: -50,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomCenter,
                  radius: 0.8,
                  colors: [
                    const Color(0xFFD4AF37).withAlpha(26),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Gold glow blobs
          Positioned(
            top: -140,
            right: -120,
            child: _StageGlow(
              size: 320,
              color: const Color(0xFFD4AF37).withAlpha(31),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -140,
            child: _StageGlow(
              size: 360,
              color: const Color(0xFFD4AF37).withAlpha(31),
            ),
          ),

          // Subtle pattern overlay (kente-inspired)
          Positioned.fill(
            child: Opacity(
              opacity: 0.03,
              child: Container(
                decoration: const BoxDecoration(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Stage glow effect
class _StageGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _StageGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 100,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}

// Custom loader that looks like a spinning stage light
class _StageLoaderPainter extends CustomPainter {
  final double progress;
  final Color color;

  _StageLoaderPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background circle
    final backgroundPaint = Paint()
      ..color = color.withAlpha(26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      arcPaint,
    );

    // Center dot
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Alternative: Minimalist version (use if you prefer cleaner look)
class SplashScreenMinimalist extends StatefulWidget {
  const SplashScreenMinimalist({super.key});

  @override
  State<SplashScreenMinimalist> createState() => _SplashScreenMinimalistState();
}

class _SplashScreenMinimalistState extends State<SplashScreenMinimalist> with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFD4AF37);

  late final AnimationController _controller;
  late final Animation<double> _fade;

  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _navTimer = Timer(const Duration(milliseconds: 2200), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Simple gold logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  border: Border.all(color: _gold, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.album,
                  color: _gold,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),

              // Brand name
              const Text(
                'WEAFRICA',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'music',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}