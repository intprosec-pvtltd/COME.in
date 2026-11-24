import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
const plum = Color(0xFF3B1E3F);
const lavender = Color(0xFFB794F6);
const blush = Color(0xFFF4D7CC);
const cream = Color(0xFFFAF8F6);
const muted = Color(0xFF817487);
const successGreen = Color(0xFF168363);
ThemeData buildPgTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: plum,
  primary: plum,
  secondary: lavender,
  surface: Colors.white);
  return ThemeData( useMaterial3: true,
  colorScheme: scheme,
  scaffoldBackgroundColor: cream,
  fontFamily: 'Roboto',
  appBarTheme: const AppBarTheme(backgroundColor: cream,
  foregroundColor: plum,
  centerTitle: false,
  elevation: 0,
  surfaceTintColor: Colors.transparent),
  cardTheme: CardThemeData(color: Colors.white,
  elevation: 0,
  surfaceTintColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23),
  side: const BorderSide(color: Color(0xFFF1EBF0)))),
  navigationBarTheme: NavigationBarThemeData(backgroundColor: Colors.white,
  indicatorColor: lavender.withValues(alpha: .20),
  labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12,
  fontWeight: FontWeight.w700))),
  inputDecorationTheme: InputDecorationTheme(filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16,
  vertical: 16),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(color: Color(0xFFE8DAE8))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(color: Color(0xFFE8DAE8)))),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: plum,
  foregroundColor: Colors.white,
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
  elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: plum,
  foregroundColor: Colors.white,
  minimumSize: const Size.fromHeight(50),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
  );
}


Color secondaryText(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFC3B8CD) : muted;

ThemeData buildPgDarkTheme() {
  const background = Color(0xFF15111C);
  const surface = Color(0xFF1D1726);
  const card = Color(0xFF282033);
  const accent = Color(0xFFC4A5FF);
  const foreground = Color(0xFFF5F3FF);
  const secondary = Color(0xFFC3B8CD);
  const outline = Color(0xFF756783);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
    primary: accent, onPrimary: background, secondary: accent,
    surface: surface, onSurface: foreground, onSurfaceVariant: secondary,
    secondaryContainer: const Color(0xFF50376D), onSecondaryContainer: foreground,
    outline: outline);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: outline));
  return ThemeData(useMaterial3: true, colorScheme: scheme,
    scaffoldBackgroundColor: background, cardColor: card, fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(backgroundColor: surface, foregroundColor: foreground,
      elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: Brightness.light, systemNavigationBarContrastEnforced: false)),
    cardTheme: CardThemeData(color: card, elevation: 0, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23))),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: surface,
      surfaceTintColor: Colors.transparent, indicatorColor: const Color(0xFF50376D),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? accent : secondary)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? accent : secondary))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: card,
      hintStyle: const TextStyle(color: secondary), border: border, enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: accent, width: 2))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: accent, side: const BorderSide(color: outline))),
  );
}
