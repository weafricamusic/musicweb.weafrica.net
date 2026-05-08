import 'package:flutter/material.dart';

class AppColors {
  static const Color grassDark = Color(0xFF1B4332);
  static const Color grassMid = Color(0xFF2D6A4F);
  static const Color grassPale = Color(0xFFB7E4C7);
  static const Color grassMint = Color(0xFF95D5B2);
  static const Color grassCream = Color(0xFFD8F3DC);
  static const Color grassBright = Color(0xFF52B788);
  
  static const Color liveRed = Color(0xFFE63946);
  static const Color battleAmber = Color(0xFFF9A825);
  static const Color battleAmberLight = Color(0xFFFDD835);
}

class AppGradients {
  static const LinearGradient grassBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B4332), Color(0xFF081C15)],
  );

  static const LinearGradient liveButton = LinearGradient(
    colors: [Color(0xFFE63946), Color(0xFFD62828)],
  );
}
