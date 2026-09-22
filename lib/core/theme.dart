import 'package:flutter/material.dart';

/// Cores extraídas 1:1 de `app/globals.css` (:root) do site original Pixgo.
/// NÃO alterar estes valores sem alterar também o site — devem ficar idênticos.
class AppColors {
  AppColors._();

  static const primary      = Color(0xFFE50914);
  static const primaryGlow  = Color(0xFFFF2A2A);
  static const secondary    = Color(0xFF1CE783);
  static const accent       = Color(0xFF8C3BFF);

  static const bgDark    = Color(0xFF0A0A0C);
  static const bgDarker  = Color(0xFF050507);
  static const cardBg    = Color(0xFF121216);
  static const cardHover = Color(0xFF1A1A20);

  static const textLight = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFA0A0A0);
  static const textTitle = Color(0xFFF1F1F1);

  static const border      = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const borderHover = Color(0x4DE50914); // rgba(229,9,20,0.3)

  // Cores por tipo de conteúdo (ContentCard.tsx TYPE_COLORS)
  static const typeMovie       = Color(0xFFE50914);
  static const typeSeries      = Color(0xFFFF6B00);
  static const typeAnime       = Color(0xFFFF0080);
  static const typeDocumentary = Color(0xFF00A8FF);
  static const typeDorama      = Color(0xFF9C27B0);
  static const typeChannel     = Color(0xFF1CE783);

  static Color forType(String? type) {
    switch (type) {
      case 'movie':       return typeMovie;
      case 'series':      return typeSeries;
      case 'anime':       return typeAnime;
      case 'documentary': return typeDocumentary;
      case 'dorama':      return typeDorama;
      case 'channel':     return typeChannel;
      default:            return typeMovie;
    }
  }
}

class AppTheme {
  AppTheme._();

  // font-main: 'Poppins', font-display: 'Montserrat' (títulos/logo)
  static const fontMain    = 'Poppins';
  static const fontDisplay = 'Montserrat';

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.primary,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.cardBg,
        error: AppColors.primary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textLight,
        displayColor: AppColors.textTitle,
        fontFamily: fontMain,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgDarker,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: AppColors.textTitle,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textLight,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgDarker,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}
