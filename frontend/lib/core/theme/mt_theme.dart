import 'package:flutter/material.dart';
import 'mt_colors.dart';
import 'mt_text_styles.dart';

class MtTheme {
  static ThemeData light({Color? primaryColor}) {
    final brandColor = primaryColor ?? MtColors.brand;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: MtColors.bg,
      primaryColor: brandColor,
      colorScheme: ColorScheme.light(
        primary: brandColor,
        secondary: MtColors.brand600,
        tertiary: MtColors.brand700,
        surface: MtColors.surface,
        error: MtColors.rejected,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: MtColors.ink,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: MtTextStyles.h2.copyWith(color: MtColors.ink),
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: brandColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MtColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: MtColors.line),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandColor,
          textStyle: MtTextStyles.labelLg,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MtColors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brandColor, width: 2),
        ),
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        labelStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MtColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: MtTextStyles.labelMd.copyWith(color: MtColors.ink2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: MtColors.line),
        ),
      ),
      cardTheme: CardThemeData(
        color: MtColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: MtColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: MtColors.line,
        thickness: 1,
        space: 16,
      ),
      textTheme: TextTheme(
        displayLarge: MtTextStyles.displayLg.copyWith(color: MtColors.ink),
        headlineLarge: MtTextStyles.h1.copyWith(color: MtColors.ink),
        headlineMedium: MtTextStyles.h2.copyWith(color: MtColors.ink),
        headlineSmall: MtTextStyles.h3.copyWith(color: MtColors.ink),
        titleLarge: MtTextStyles.sectionLabel.copyWith(color: MtColors.ink3),
        bodyLarge: MtTextStyles.bodyLg.copyWith(color: MtColors.ink2),
        bodyMedium: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        bodySmall: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        labelLarge: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
        labelMedium: MtTextStyles.labelMd.copyWith(color: MtColors.ink2),
        labelSmall: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
      ),
    );
  }

  static ThemeData dark({Color? primaryColor}) {
    final brandColor = primaryColor ?? MtColors.brand;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      primaryColor: brandColor,
      colorScheme: ColorScheme.dark(
        primary: brandColor,
        secondary: MtColors.brand600,
        tertiary: MtColors.brand700,
        surface: const Color(0xFF1E293B),
        error: MtColors.rejected,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: MtTextStyles.h2.copyWith(color: Colors.white),
      ),
      textTheme: TextTheme(
        displayLarge: MtTextStyles.displayLg.copyWith(color: Colors.white),
        headlineLarge: MtTextStyles.h1.copyWith(color: Colors.white),
        headlineMedium: MtTextStyles.h2.copyWith(color: Colors.white),
        headlineSmall: MtTextStyles.h3.copyWith(color: Colors.white),
        titleLarge: MtTextStyles.sectionLabel.copyWith(color: Colors.white70),
        bodyLarge: MtTextStyles.bodyLg.copyWith(color: Colors.white),
        bodyMedium: MtTextStyles.bodyMd.copyWith(color: Colors.white70),
        bodySmall: MtTextStyles.bodySm.copyWith(color: Colors.white54),
        labelLarge: MtTextStyles.labelLg.copyWith(color: Colors.white),
        labelMedium: MtTextStyles.labelMd.copyWith(color: Colors.white70),
        labelSmall: MtTextStyles.labelSm.copyWith(color: Colors.white54),
      ),
    );
  }
}
