import 'package:flutter/material.dart';

const ink = Color(0xFF24342D);
const muted = Color(0xFF526358);
const accent = Color(0xFF356657);
const canvas = Color(0xFFEBEEE8);
const paper = Color(0xFFF6F7F3);
const sidebar = Color(0xFF24382F);
const line = Color(0xFFCCD6CD);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: muted,
    onPrimary: paper,
    outline: const Color(0xFF84958A),
    outlineVariant: line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Manrope',
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ink,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: muted,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    dividerColor: line,
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFBFCF8),
      labelStyle: const TextStyle(
        color: muted,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(color: muted, fontWeight: FontWeight.w400),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFE8EDE6)),
      headingTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      dataTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: ink,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      dataRowMinHeight: 66,
      dataRowMaxHeight: 78,
      columnSpacing: 24,
      horizontalMargin: 20,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
