import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'weafrica_colors.dart';

/// Premium 2025 theme surface.
///
/// This is intentionally compatible with the existing app palette and widgets,
/// but provides the new names/layout used by the refactored architecture.
class WeAfricaTheme {
  static ThemeData get light {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      brightness: Brightness.dark,
      primaryColor: WeAfricaColors.gold,
      scaffoldBackgroundColor: WeAfricaColors.stageBlack,
      colorScheme: base.colorScheme.copyWith(
        primary: WeAfricaColors.gold,
        secondary: WeAfricaColors.goldLight,
        surface: WeAfricaColors.surfaceDark,
        error: WeAfricaColors.error,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: WeAfricaColors.textPrimary,
        displayColor: WeAfricaColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: WeAfricaColors.gold,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
        iconTheme: const IconThemeData(color: WeAfricaColors.gold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: WeAfricaColors.surfaceDark,
        selectedItemColor: WeAfricaColors.gold,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: WeAfricaColors.gold,
        labelColor: WeAfricaColors.gold,
        unselectedLabelColor: Colors.white54,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WeAfricaColors.gold,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WeAfricaColors.gold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WeAfricaColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: WeAfricaColors.textMuted),
        hintStyle: const TextStyle(color: WeAfricaColors.textDisabled),
      ),
    );
  }

  static ThemeData get dark => light;
}
