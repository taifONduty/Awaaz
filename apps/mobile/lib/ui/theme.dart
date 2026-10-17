import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AwaazColors {
  static const canvas = Color(0xFFF5F6F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF172126);
  static const muted = Color(0xFF59666B);
  static const primary = Color(0xFF0C5B49);
  static const tint = Color(0xFFE1F0E5);
  static const accent = Color(0xFFD3EDAB);
  static const border = Color(0xFFE1E5E7);
  static const warning = Color(0xFF80510C);
  static const warningTint = Color(0xFFFFF0D2);
  static const danger = Color(0xFFB73535);
  static const dangerTint = Color(0xFFFFE8E5);
  static const map = Color(0xFFF0F2F3);
  static const water = Color(0xFFC5E1EB);
  static const park = Color(0xFFDCE9D7);
}

Duration uiMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

ThemeData awaazTheme(bool bangla) {
  final scheme = ColorScheme.fromSeed(seedColor: AwaazColors.primary).copyWith(
    primary: AwaazColors.primary,
    onPrimary: Colors.white,
    surface: AwaazColors.surface,
    onSurface: AwaazColors.ink,
    error: AwaazColors.danger,
    primaryContainer: AwaazColors.tint,
    outline: AwaazColors.border,
    secondaryContainer: AwaazColors.accent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AwaazColors.canvas,
    fontFamily: bangla ? 'Noto Sans Bengali' : 'Manrope',
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge!.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.22,
        letterSpacing: -.7,
      ),
      headlineSmall: base.textTheme.headlineSmall!.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -.5,
      ),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: base.textTheme.bodySmall!.copyWith(
        fontSize: 12,
        height: 1.45,
        color: AwaazColors.muted,
      ),
      labelLarge: base.textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AwaazColors.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AwaazColors.ink,
        letterSpacing: -.7,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.white,
      indicatorColor: AwaazColors.tint,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AwaazColors.ink,
        ),
      ),
      iconTheme: WidgetStateProperty.all(
        const IconThemeData(color: AwaazColors.primary, size: 24),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AwaazColors.tint,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AwaazColors.tint,
      side: const BorderSide(color: AwaazColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(
        fontSize: 13,
        color: AwaazColors.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AwaazColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AwaazColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AwaazColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
  );
}
