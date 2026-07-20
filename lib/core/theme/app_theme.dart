import 'package:flutter/material.dart';

// 2026 "Out of This World" Concepts
enum HuntingConcept { thermalGlow, walnutLuxury, neonShock }

class ThemeController extends ChangeNotifier {
  HuntingConcept _currentConcept = HuntingConcept.walnutLuxury;
  bool _isDarkMode = false;

  HuntingConcept get currentConcept => _currentConcept;
  bool get isDarkMode => _isDarkMode;

  void setConcept(HuntingConcept concept) {
    _currentConcept = concept;
    notifyListeners();
  }

  void toggleThemeMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  // --- ATMOSPHERIC BACKGROUNDS ---
  Color get backgroundColor {
    if (_isDarkMode) {
      switch (_currentConcept) {
        case HuntingConcept.thermalGlow: return const Color(0xFF432F16); // Embered Clay
        case HuntingConcept.walnutLuxury: return const Color(0xFF1A1412); // Deep Espresso
        case HuntingConcept.neonShock: return const Color(0xFF2C3124); // Shadowed Olive
      }
    } else {
      switch (_currentConcept) {
        case HuntingConcept.thermalGlow: return const Color(0xFFFFF1E6); // Warm Sand
        case HuntingConcept.walnutLuxury: return const Color(0xFFFDF8F5); // Warm Parchment
        case HuntingConcept.neonShock: return const Color(0xFFE7E3CD); // Soft Khaki
      }
    }
  }

  // --- PRECISION ACCENTS ---
  Color get accentColor {
    if (_isDarkMode) {
      switch (_currentConcept) {
        case HuntingConcept.thermalGlow: return const Color(0xFFFF7A18); // Kalahari Orange
        case HuntingConcept.walnutLuxury: return const Color(0xFFD4AF37); // Brushed Gold
        case HuntingConcept.neonShock: return const Color(0xFF8C9A6B); // Sage Olive
      }
    } else {
      switch (_currentConcept) {
        case HuntingConcept.thermalGlow: return const Color(0xFFCC6600); // Burnt Amber
        case HuntingConcept.walnutLuxury: return const Color(0xFF8B4513); // Saddle Brown
        case HuntingConcept.neonShock: return const Color(0xFF718355); // Bushveld Sage
      }
    }
  }

  // --- DYNAMIC TEXT ---
  Color get textColor => _isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
  Color get subtitleColor => _isDarkMode ? Colors.white60 : Colors.black54;

  // --- TACTILE CARD SURFACE ---
  Color get cardColor {
    return _isDarkMode 
      ? backgroundColor.withAlpha(150) 
      : Colors.white.withAlpha(230);
  }

  // --- MATERIAL THEME OVERRIDE ---
  ThemeData get materialTheme {
    final scheme = ColorScheme(
      brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      primary: accentColor,
      onPrimary: backgroundColor,
      secondary: accentColor.withValues(alpha: 0.92),
      onSecondary: backgroundColor,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      surface: backgroundColor,
      onSurface: textColor,
      surfaceContainerHighest: cardColor,
      onSurfaceVariant: textColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        iconTheme: IconThemeData(color: accentColor),
        titleTextStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 20),
        elevation: 0,
      ),
      cardColor: cardColor,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: backgroundColor,
        ),
      ),
      textTheme: Typography.material2021().black.apply(bodyColor: textColor, displayColor: textColor),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => accentColor),
        trackColor: WidgetStateProperty.resolveWith((states) => accentColor.withValues(alpha: 0.4)),
      ),
    );
  }
}
