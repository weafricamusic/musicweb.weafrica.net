import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand-aligned dark palette (matches assets/images/Designer.png)
  static const background = Color(0xFF0B0614);
  static const surface = Color(0xFF141022);
  static const surface2 = Color(0xFF1B1530);
  static const text = Color(0xFFF7F3FF);
  static const textMuted = Color(0xFFBDAED6);
  static const border = Color(0xFF2D2545);

  // ---------------------------------------------------------------------------
  // Compatibility aliases (older screens expect these names).
  // Keep values mapped to existing tokens to avoid introducing new colors.
  // ---------------------------------------------------------------------------
  static const backgroundDark = background;
  static const surfaceDark = surface;
  static const surfaceLight = surface2;

  static const textSecondary = textMuted;

  static const brandGold = stageGold;

  // Semantic aliases used by some legacy dashboards.
  static const live = brandBlue;
  static const pending = brandPink;
  static const success = stageGold;
  static const warning = stageGold;
  static const info = brandBlue;
  static const error = brandBlue;

  // THE STAGE accents (WEAFRICA Studio identity)
  static const stageGold = Color(0xFFF28C1E); // brand orange
  static const stagePurple = Color(0xFF5A2BA6); // brand purple

  // Brand accents (Gold-driven). Names kept for compatibility across the codebase.
  static const brandOrange = stageGold;
  static const brandPink = Color(0xFFD04984); // magenta/pink from gradient
  static const brandPurple = stagePurple;
  static const brandBlue = Color(0xFF2A83FF);
}

ThemeData buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final colorScheme = base.colorScheme.copyWith(
    brightness: Brightness.dark,
    primary: AppColors.brandOrange,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF3A2106),
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.brandPurple,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF26133F),
    onSecondaryContainer: AppColors.text,
    tertiary: AppColors.brandPink,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFF3A1025),
    onTertiaryContainer: AppColors.text,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surface2,
    outline: AppColors.border,
    error: const Color(0xFFFF4D6D),
    onError: Colors.white,
    errorContainer: const Color(0xFF3A0F1B),
    onErrorContainer: AppColors.text,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: colorScheme,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: AppColors.text),
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.brandOrange),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        textStyle: WidgetStatePropertyAll(
          GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(AppColors.brandOrange),
        textStyle: WidgetStatePropertyAll(
          GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.brandOrange, width: 1.2),
      ),
      hintStyle: TextStyle(color: AppColors.textMuted),
      labelStyle: TextStyle(color: AppColors.textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

ThemeData buildLightTheme() {
  const background = Color(0xFFF7F7FB);
  const surface = Colors.white;
  const surface2 = Color(0xFFF0F1F7);
  const border = Color(0xFFE3E5F0);
  const text = Color(0xFF14141E);
  const textMuted = Color(0xFF5E6175);

  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: base.colorScheme.copyWith(
      surface: surface,
      primary: AppColors.brandOrange,
      secondary: AppColors.brandPurple,
      tertiary: AppColors.brandPink,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.brandOrange, width: 1.2),
      ),
      hintStyle: TextStyle(color: textMuted),
      labelStyle: TextStyle(color: textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
