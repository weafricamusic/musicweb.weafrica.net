// lib/screens/studio/studio_entry_screen.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/constants/weafrica_power_voice.dart';
import '../../../app/theme.dart';
import '../../../app/services/motivation_service.dart';
import '../../artist_dashboard/screens/artist_dashboard_screen.dart';
import '../../auth/user_role.dart';
import '../../dj_dashboard/screens/dj_dashboard_screen.dart';

class StudioEntryScreen extends StatefulWidget {
  const StudioEntryScreen({
    super.key,
    required this.role,
    required this.isActive,
    required this.openTick,
    this.maxMotivationsPerDay = 1, // Configurable
  });

  final UserRole role;
  final bool isActive;
  final int openTick;
  final int maxMotivationsPerDay;

  @override
  State<StudioEntryScreen> createState() => _StudioEntryScreenState();
}

class _StudioEntryScreenState extends State<StudioEntryScreen>
    with SingleTickerProviderStateMixin {
  // Keep fades quick but readable, and scale the hold time with message length.
  static const Duration _fadeIn = Duration(milliseconds: 450);
  static const Duration _fadeOut = Duration(milliseconds: 450);
  static const Duration _minHold = Duration(milliseconds: 2200);
  static const Duration _maxHold = Duration(milliseconds: 6500);

  late final AnimationController _controller;
  late Animation<double> _opacity;

  int _lastOpenTick = -1;
  bool _showMotivation = false;
  String _message = '';
  
  Timer? _fallbackTimer;
  MotivationService? _motivationService;

  @override
  void initState() {
    super.initState();
    
    _initMotivationService();

    _controller = AnimationController(
      vsync: this,
      duration: _fadeIn + _minHold + _fadeOut,
    );
    _configureOpacity(hold: _minHold);

    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showMotivation = false);
      }
    });
  }

  Duration _holdForMessage(String message) {
    final text = message.trim();
    if (text.isEmpty) return _minHold;

    // Rough reading-time estimate (kept simple): base + ms/word, clamped.
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final estimatedMs = 900 + (words * 350);
    final holdMs = estimatedMs.clamp(
      _minHold.inMilliseconds,
      _maxHold.inMilliseconds,
    );
    return Duration(milliseconds: holdMs);
  }

  void _configureOpacity({required Duration hold}) {
    // Update controller duration to match the new hold time.
    _controller.duration = _fadeIn + hold + _fadeOut;

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: _fadeIn.inMilliseconds.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: hold.inMilliseconds.toDouble(),
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: _fadeOut.inMilliseconds.toDouble(),
      ),
    ]).animate(_controller);
  }

  Future<void> _initMotivationService() async {
    final prefs = await SharedPreferences.getInstance();
    _motivationService = MotivationService(prefs);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudioEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only trigger when the Studio tab becomes active
    if (!widget.isActive) return;

    // Replay motivation any time openTick changes
    if (widget.openTick != _lastOpenTick) {
      _lastOpenTick = widget.openTick;
      _checkAndStartMotivation();
    }
  }

  Future<void> _checkAndStartMotivation() async {
    // Wait for service to initialize if needed
    if (_motivationService == null) {
      await _initMotivationService();
    }
    
    // Check if we should show motivation today
    final shouldShow = await _motivationService?.shouldShowMotivation(
          maxPerDay: widget.maxMotivationsPerDay,
        ) ??
        true;
    
    if (shouldShow) {
      await _startMotivation();
      await _motivationService?.recordMotivationShown();
    } else {
      // Skip motivation, go straight to dashboard
      if (mounted) {
        setState(() => _showMotivation = false);
      }
    }
  }

  Future<void> _startMotivation() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').trim();
    final who = name.isEmpty ? 'Artist' : name;

    final messageIndex = await _motivationService
      ?.getNextMessageIndex(WeAfricaPowerVoice.coreMessagesCount);

    final message = WeAfricaPowerVoice.studioMotivation(
      who: who,
      messageIndex: messageIndex,
    );

    final hold = _holdForMessage(message);
    _configureOpacity(hold: hold);

    setState(() {
      _message = message;
      _showMotivation = true;
    });

    _controller
      ..stop()
      ..reset()
      ..forward();

    // Safety: ensure we always transition even if animation is interrupted
    final total = _controller.duration ?? (_fadeIn + hold + _fadeOut);
    _fallbackTimer = Timer(total + const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _showMotivation = false);
    });
  }

  Widget _dashboardForRole() {
    return switch (widget.role) {
      UserRole.artist => const ArtistDashboardScreen(),
      UserRole.dj => const DjDashboardScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboardForRole();

    // If this tab is first built while already active (rare), ensure we start
    if (widget.isActive && _lastOpenTick == -1) {
      _lastOpenTick = widget.openTick;
      // Post-frame so we don't setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkAndStartMotivation();
      });
    }

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            final isShowingDashboard = child.key == const ValueKey('dashboard');
            final slide = Tween<Offset>(
              begin: isShowingDashboard ? const Offset(0.08, 0) : Offset.zero,
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

            return FadeTransition(
              opacity: anim,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: _showMotivation
              ? const SizedBox(key: ValueKey('motivation'))
              : KeyedSubtree(
                  key: const ValueKey('dashboard'),
                  child: dashboard,
                ),
        ),
        if (_showMotivation)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: AnimatedBuilder(
                animation: _opacity,
                builder: (context, _) {
                  final o = _opacity.value;

                  return Opacity(
                    opacity: o,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 22),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.brandOrange.withValues(alpha: 0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandOrange.withValues(
                                alpha: 0.22 * o,
                              ),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}