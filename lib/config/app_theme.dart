import 'package:flutter/material.dart';

/// The only place app colors are defined. Widgets read them from `Theme.of(context).colorScheme`;
/// status colors that have no colorScheme slot (success / warning) come from [AppColors] directly.
abstract final class AppColors {
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF1C1C22);
  static const primary = Color(0xFF6366F1); // indigo
  static const secondary = Color(0xFFEC4899); // pink

  /// Filled destructive actions / error snackbars; white text on it is 5.0:1 (WCAG AA).
  static const error = Color(0xFFD32F2F);

  /// Error text and icons on dark surfaces (≈8:1 on [background]) → `colorScheme.onErrorContainer`.
  static const errorText = Color(0xFFFF8A80);

  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFF5C1A1A),
    onErrorContainer: AppColors.errorText,
  ),
  fontFamily: 'Inter',
  useMaterial3: true,
);

/// Form input look (CRUD forms, form builder): filled surface, rounded 16, primary focus border.
InputDecoration fieldDecoration(ColorScheme scheme, {String? label, String? hint, String? helper}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
    labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
    filled: true,
    fillColor: scheme.surface.withValues(alpha: 0.7),
    border: border(scheme.onSurface.withValues(alpha: 0.1)),
    enabledBorder: border(scheme.onSurface.withValues(alpha: 0.1)),
    focusedBorder: border(scheme.primary),
  );
}
