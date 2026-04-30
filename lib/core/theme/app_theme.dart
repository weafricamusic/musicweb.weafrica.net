import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBackground = Color(0xFF0A0A0F);
  static const Color cardBackground = Color(0xFF15151E);
  static const Color surfaceColor = Color(0xFF1E1E2E);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color accentPink = Color(0xFFE879F9);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentGold = Color(0xFFFBBF24);
  static const Color successGreen = Color(0xFF34D399);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color liveRed = Color(0xFFFF4444);

  static ThemeData get darkTheme => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: darkBackground,
        primaryColor: primaryPurple,
        colorScheme: const ColorScheme.dark(
          primary: primaryPurple,
          secondary: accentPink,
          surface: surfaceColor,
          background: darkBackground,
          error: dangerRed,
        ),
      );
}