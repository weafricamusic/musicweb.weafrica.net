import 'package:flutter/material.dart';

import '../theme.dart';

/// Stage palette alias used by the refactored Artist Dashboard.
///
/// Note: This intentionally maps most values to existing [AppColors]
/// so the wider app palette stays consistent.
class WeAfricaColors {
  static const Color gold = AppColors.stageGold;
  static const Color goldLight = Color(0xFFF2D572);
  static const Color goldDark = Color(0xFF8B6910);

  static const Color deepIndigo = AppColors.background;
  static const Color stageBlack = AppColors.background;

  static const Color surfaceDark = AppColors.surface;
  static const Color cardDark = AppColors.surface2;

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Text
  static const Color textPrimary = AppColors.text;
  static const Color textSecondary = AppColors.text;
  static const Color textMuted = AppColors.textMuted;
  static const Color textDisabled = Color(0x66FFFFFF);

  // Opacity helpers
  static Color goldWithOpacity(double opacity) => gold.withValues(alpha: opacity);
  static Color whiteWithOpacity(double opacity) => Colors.white.withValues(alpha: opacity);
  static Color blackWithOpacity(double opacity) => Colors.black.withValues(alpha: opacity);
}
