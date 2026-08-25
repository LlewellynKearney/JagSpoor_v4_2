import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JagSpoor official tactical theme palette.
///
/// All screens should source colors from [Theme.of] (which is seeded from
/// [ThemeController.lightTheme] / [ThemeController.darkTheme]) or directly from
/// these constants — never raw `Colors.white`/`Colors.black` — so the Day/Night
/// toggle updates every screen uniformly.
class AppColors {
  AppColors._();

  // --- Dark Mode / Night Tactical ---
  static const Color darkBackground = Color(0xFF121212); // Obsidian Black
  static const Color darkBackgroundAlt = Color(0xFF1A1A1A); // Obsidian (raised)
  static const Color darkCard = Color(0xFF262626); // Panel Card Dark Earth
  static const Color darkAccent = Color(0xFFC68B59); // Warm Gold/Bronze
  static const Color darkAccentAlt = Color(0xFFD4AF37); // Brushed Gold
  static const Color darkText = Color(0xFFE0E0E0); // High-Contrast Off-White
  static const Color darkSubtitle = Color(0xFFB0B0B0);

  // --- Light Mode / Day Tactical ---
  static const Color lightBackground = Color(0xFFF4EFEA); // Crisp Light Earth
  static const Color lightCard = Color(0xFFFFFFFF); // Card White
  static const Color lightAccent = Color(0xFF795548); // Deep Saddle Brown
  static const Color lightAccentAlt = Color(0xFF8D6E63); // Saddle Brown
  static const Color lightText = Color(0xFF212121); // Dark Charcoal
  static const Color lightSubtitle = Color(0xFF5D4037);

  static const Color error = Color(0xFFEF4444);
}

/// Central Day/Night theme controller. Persists the chosen mode to
/// SharedPreferences so it survives restarts, and exposes both the current-mode
/// color getters (for legacy screen consumers) and separate [lightTheme] /
/// [darkTheme] [ThemeData]s for [MaterialApp.theme] / [MaterialApp.darkTheme].
///
/// Call [init] once at startup (before `runApp`) to load the saved preference.
class ThemeController extends ChangeNotifier {
  static const String _prefsKey = 'jagspoor_dark_mode';

  /// Process-wide singleton. Constructed lazily on first access; mirrors the
  /// instance created in `main()` (which is the one actually driving the
  /// app's `MaterialApp`). Callers that need a `ThemeController` outside the
  /// widget tree (e.g. a shim pushed from a stateless context) should use this
  /// so they read the same persisted Day/Night preference.
  static ThemeController get instance => _instance ??= ThemeController();
  static ThemeController? _instance;

  bool _isDarkMode = false;
  bool _initialized = false;

  bool get isDarkMode => _isDarkMode;

  /// Material [ThemeMode] for [MaterialApp.themeMode].
  ThemeMode get themeMode =>
      _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Load the persisted theme preference. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      _isDarkMode = false;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, _isDarkMode);
    } catch (_) {}
  }

  /// Toggles Day ↔ Night and persists the choice. The [MaterialApp] rebuilds
  /// instantly via the [AnimatedBuilder] wrapping this controller.
  void toggleThemeMode() {
    _isDarkMode = !_isDarkMode;
    _persist();
    notifyListeners();
  }

  /// Explicitly set the mode (used by profile/settings toggles).
  void setDarkMode(bool dark) {
    if (_isDarkMode == dark) return;
    _isDarkMode = dark;
    _persist();
    notifyListeners();
  }

  // --- ATMOSPHERIC BACKGROUNDS ---
  Color get backgroundColor =>
      _isDarkMode ? AppColors.darkBackground : AppColors.lightBackground;

  // --- PRECISION ACCENTS ---
  Color get accentColor =>
      _isDarkMode ? AppColors.darkAccent : AppColors.lightAccent;

  // --- DYNAMIC TEXT ---
  Color get textColor =>
      _isDarkMode ? AppColors.darkText : AppColors.lightText;
  Color get subtitleColor =>
      _isDarkMode ? AppColors.darkSubtitle : AppColors.lightSubtitle;

  // --- TACTILE CARD SURFACE ---
  Color get cardColor =>
      _isDarkMode ? AppColors.darkCard : AppColors.lightCard;

  // --- MATERIAL THEME (current mode, retained for legacy consumers) ---
  ThemeData get materialTheme =>
      _isDarkMode ? darkTheme : lightTheme;

  /// Day / Light tactical theme.
  ThemeData get lightTheme => _buildTheme(Brightness.light);

  /// Night / Dark tactical theme.
  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  /// The [SystemUiOverlayStyle] that matches the active theme's brightness.
  /// On the light theme the status-bar icons are dark (so the phone's battery,
  /// Wi-Fi, and clock are clearly visible against the light background); on
  /// the dark theme they are light. Exposed so [main]'s `MaterialApp` can wrap
  /// itself in an `AnnotatedRegion<SystemUiOverlayStyle>` and so individual
  /// screens with transparent AppBars inherit the right contrast.
  SystemUiOverlayStyle get systemOverlayStyle =>
      _isDarkMode ? _darkOverlay : _lightOverlay;

  static const SystemUiOverlayStyle _lightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // dark icons on light bg
    statusBarBrightness: Brightness.light, // iOS: light bg -> dark icons
    systemNavigationBarColor: Color(0xFFF4EFEA),
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static const SystemUiOverlayStyle _darkOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // light icons on dark bg
    statusBarBrightness: Brightness.dark, // iOS: dark bg -> light icons
    systemNavigationBarColor: Color(0xFF121212),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.darkBackground : AppColors.lightBackground;
    final card = dark ? AppColors.darkCard : AppColors.lightCard;
    final accent = dark ? AppColors.darkAccent : AppColors.lightAccent;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    final overlay = dark ? _darkOverlay : _lightOverlay;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: dark ? AppColors.darkText : Colors.white,
      secondary: accent.withValues(alpha: 0.92),
      onSecondary: dark ? AppColors.darkText : Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: bg,
      onSurface: text,
      surfaceContainerHighest: card,
      onSurfaceVariant: text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        iconTheme: IconThemeData(color: accent),
        titleTextStyle: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        elevation: 0,
        // Ensures the status-bar icons contrast with the AppBar background
        // even for screens that don't set their own AnnotatedRegion.
        systemOverlayStyle: overlay,
      ),
      cardColor: card,
      dividerColor: accent.withValues(alpha: 0.25),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? AppColors.darkText : Colors.white,
        ),
      ),
      textTheme: Typography.material2021().black.apply(
        bodyColor: text,
        displayColor: text,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => accent.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
