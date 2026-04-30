import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/gift_controller.dart';
import '../../models/gift_model.dart';

class GiftAnimationOverlay extends StatelessWidget {
  const GiftAnimationOverlay({super.key});

  Duration _durationFor(GiftModel gift) {
    switch (gift.type) {
      case GiftType.rocket:
      case GiftType.rainbow:
        return const Duration(milliseconds: 2600);
      case GiftType.fireworks:
      case GiftType.crown:
        return const Duration(milliseconds: 2300);
      case GiftType.balloon:
        return const Duration(milliseconds: 2800);
      default:
        return const Duration(milliseconds: 2000);
    }
  }

  double _travelFor(GiftModel gift) {
    switch (gift.type) {
      case GiftType.rocket:
        return 320;
      case GiftType.balloon:
        return 260;
      case GiftType.fireworks:
        return 240;
      case GiftType.rainbow:
        return 180;
      default:
        return 210;
    }
  }

  double _sizeFor(GiftModel gift) {
    switch (gift.type) {
      case GiftType.crown:
      case GiftType.rainbow:
        return 32;
      case GiftType.rocket:
      case GiftType.fireworks:
        return 30;
      default:
        return 26;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GiftController>(
      builder: (context, controller, _) {
        return Stack(
          children: controller.activeGifts.map((gift) {
            final duration = _durationFor(gift);
            final travel = _travelFor(gift);
            final iconSize = _sizeFor(gift);

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: duration,
              curve: Curves.easeOutCubic,
              builder: (context, progress, child) {
                final verticalOffset = -travel * progress;
                final horizontalOffset = switch (gift.type) {
                  GiftType.balloon => math.sin(progress * math.pi * 2.2) * 18,
                  GiftType.rainbow => math.sin(progress * math.pi) * 28,
                  GiftType.star => math.cos(progress * math.pi * 2) * 10,
                  _ => math.sin(progress * math.pi * 1.6) * 6,
                };
                final scale = switch (gift.type) {
                  GiftType.fireworks => 1 + (math.sin(progress * math.pi) * 0.35),
                  GiftType.crown => 1 + (math.sin(progress * math.pi) * 0.18),
                  GiftType.rainbow => 1 + (math.sin(progress * math.pi) * 0.22),
                  _ => 1 + (math.sin(progress * math.pi) * 0.08),
                };
                final opacity = (1 - (progress * 0.92)).clamp(0.0, 1.0);
                final turns = switch (gift.type) {
                  GiftType.rocket => 0.06,
                  GiftType.balloon => math.sin(progress * math.pi) * 0.025,
                  GiftType.fireworks => progress * 0.08,
                  _ => 0.0,
                };

                return Positioned(
                  left: 100 + (gift.id.hashCode % 200),
                  bottom: 100,
                  child: Transform.translate(
                    offset: Offset(horizontalOffset, verticalOffset),
                    child: Transform.rotate(
                      angle: turns * math.pi * 2,
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(opacity: opacity, child: child),
                      ),
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: gift.color.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: gift.color.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(gift.icon, color: Colors.white, size: iconSize),
                    const SizedBox(width: 8),
                    Text(
                      gift.displayName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}