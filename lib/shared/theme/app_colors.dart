import 'package:flutter/material.dart';

class AppColors {
  // Legacy import used by a few older screens.
  // Keep these values aligned with lib/app/theme.dart so the app stays consistent.
  static const Color brandOrange = Color(0xFFF28C1E);
  static const Color textMuted = Color(0xFFBDAED6);
  static const Color surface = Color(0xFF141022);
  static const Color surface2 = Color(0xFF1B1530);
  static const Color border = Color(0xFF2D2545);

  // Grass theme for live screens
  static const Color grassDark = Color(0xFF0B3D2E);
  static const Color grassMid = Color(0xFF145A32);
  static const Color grassLight = Color(0xFF1E8449);
  static const Color grassMint = Color(0xFF00E676);
  static const Color grassBright = Color(0xFF66FFA6);

  // Battle theme colors
  static const Color battleAmber = Color(0xFFFFA000);
  static const Color battleAmberLight = Color(0xFFFFD54F);
  static const Color liveRed = Color(0xFFD50000);

  // Universal colors
  static const Color coinGold = Color(0xFFFFC107);
  static const Color white20 = Color(0x33FFFFFF); // 20% white opacity
  static const Color white25 = Color(0x40FFFFFF); // 25% white opacity
}
