import 'package:flutter/material.dart';
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
