import 'package:flutter/material.dart';

class AppTheme {
  static const Color pastelGreen = Color(0xFFE7F3E4);
  static const Color cardGreen = Color(0xFFF6FBF5);
  static const Color darkGreen = Color(0xFF2F5D3A);
  static const Color borderGreen = Color(0xFF9AB89A);
  static const Color textBlack = Color(0xFF111111);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: pastelGreen,
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkGreen,
        brightness: Brightness.light,
      ),
      fontFamily: 'Times New Roman',
      appBarTheme: const AppBarTheme(
        backgroundColor: pastelGreen,
        foregroundColor: textBlack,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textBlack,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: 'Times New Roman',
        ),
      ),
      cardTheme: CardThemeData(
        color: cardGreen,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderGreen),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkGreen,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Times New Roman',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}
