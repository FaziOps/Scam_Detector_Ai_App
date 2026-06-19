// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0F1419);
  static const surface = Color(0xFF1A2332);
  static const surfaceLight = Color(0xFF243044);
  static const primary = Color(0xFF4A90E2);
  static const text = Color(0xFFE8EDF4);
  static const textMuted = Color(0xFF8A99AD);
  static const border = Color(0xFF2D3B4F);

  static const low = Color(0xFF3DDC84);
  static const medium = Color(0xFFFFC857);
  static const high = Color(0xFFFF8A3D);
  static const critical = Color(0xFFFF4D4D);
}

Color riskColor(String riskLevel) {
  switch (riskLevel) {
    case 'Low Risk':
      return AppColors.low;
    case 'Medium Risk':
      return AppColors.medium;
    case 'High Risk':
      return AppColors.high;
    case 'Critical Risk':
      return AppColors.critical;
    default:
      return AppColors.textMuted;
  }
}

Color severityColor(String severity) {
  switch (severity) {
    case 'low':
      return AppColors.low;
    case 'medium':
      return AppColors.medium;
    case 'high':
      return AppColors.high;
    case 'critical':
      return AppColors.critical;
    default:
      return AppColors.textMuted;
  }
}

final appTheme = ThemeData(
  colorScheme: const ColorScheme.dark(
    surface: AppColors.surface,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    onSurface: AppColors.text,
  ),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.text,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: AppColors.text,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textMuted,
    type: BottomNavigationBarType.fixed,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.all(14),
  ),
  useMaterial3: true,
);
