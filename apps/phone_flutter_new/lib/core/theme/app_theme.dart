import 'package:flutter/material.dart';

import 'app_dimensions.dart';

class AppTheme {
  /// RecoverySense 0.5.3 palette.
  ///
  /// The primary green is sampled from the supplied rounded-button reference.
  /// Dark text is used on the brighter green to preserve readable contrast.
  static const Color primaryGreen = Color(0xFF4F9B17);
  static const Color primaryGreenDark = Color(0xFF356E0C);
  static const Color softGreen = Color(0xFFEAF6DF);
  static const Color surfaceGreen = Color(0xFFF8FBF4);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color borderGreen = Color(0xFFCDE4B9);
  static const Color textBlack = Color(0xFF111111);
  static const Color textMuted = Color(0xFF5D655B);

  // Backward-compatible aliases used by older widgets.
  static const Color pastelGreen = surfaceGreen;
  static const Color cardGreen = cardSurface;
  static const Color darkGreen = primaryGreenDark;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
      surface: cardSurface,
    ).copyWith(
      primary: primaryGreen,
      onPrimary: textBlack,
      primaryContainer: softGreen,
      onPrimaryContainer: primaryGreenDark,
      surface: cardSurface,
      onSurface: textBlack,
      outline: borderGreen,
    );

    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surfaceGreen,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceGreen,
        foregroundColor: textBlack,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textBlack,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          side: const BorderSide(color: borderGreen),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          borderSide: const BorderSide(color: borderGreen),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          borderSide: const BorderSide(color: borderGreen),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: primaryGreen,
        thumbColor: primaryGreen,
        inactiveTrackColor: softGreen,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: textBlack,
          disabledBackgroundColor: softGreen,
          disabledForegroundColor: textMuted,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          shape: roundedShape,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: textBlack,
          disabledBackgroundColor: softGreen,
          disabledForegroundColor: textMuted,
          shape: roundedShape,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreenDark,
          side: const BorderSide(color: primaryGreen),
          shape: roundedShape,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreenDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: softGreen,
        elevation: 8,
        height: 68,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: roundedShape,
      ),
    );
  }
}
