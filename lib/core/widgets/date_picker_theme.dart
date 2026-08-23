import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Mode-aware [showDatePicker] theme builder.
///
/// The trophy / booking date pickers previously forced a
/// [ColorScheme.light] regardless of the active mode, which rendered dark
/// text on the app's dark surface (illegible in Night mode). This helper
/// resolves the picker ColorScheme from the [ThemeController] so calendar
/// text, day numbers, month headers and the OK/Cancel actions stay legible
/// on both Day and Night themes.
class JagSpoorDatePickerTheme {
  JagSpoorDatePickerTheme._();

  /// Resolves the picker [ThemeData] for the current [theme].
  ///
  /// In Night mode a [ColorScheme.dark] is used (light `onSurface` text on
  /// the dark card surface); in Day mode a [ColorScheme.light] is used.
  /// The caller-supplied [ThemeController] decides the mode so the picker
  /// follows the app-wide toggle (not just the ambient platform brightness).
  static ThemeData resolve(ThemeData base, ThemeController theme) {
    if (theme.isDarkMode) {
      return base.copyWith(
        colorScheme: ColorScheme.dark(
          primary: theme.accentColor,
          onPrimary: theme.backgroundColor,
          surface: theme.cardColor,
          onSurface: theme.textColor,
        ),
      );
    }
    return base.copyWith(
      colorScheme: ColorScheme.light(
        primary: theme.accentColor,
        onPrimary: Colors.white,
        surface: theme.cardColor,
        onSurface: theme.textColor,
      ),
    );
  }
}
