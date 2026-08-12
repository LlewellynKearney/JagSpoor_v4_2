import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('init() loads persisted dark-mode preference', () async {
      SharedPreferences.setMockInitialValues({'jagspoor_dark_mode': true});
      final controller = ThemeController();
      await controller.init();
      expect(controller.isDarkMode, isTrue);
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('init() defaults to light when no preference stored', () async {
      final controller = ThemeController();
      await controller.init();
      expect(controller.isDarkMode, isFalse);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('setDarkMode persists the choice to SharedPreferences', () async {
      final controller = ThemeController();
      await controller.init();
      controller.setDarkMode(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('jagspoor_dark_mode'), isTrue);
      expect(controller.isDarkMode, isTrue);
    });

    test('toggleThemeMode flips mode and persists', () async {
      final controller = ThemeController();
      await controller.init();
      expect(controller.isDarkMode, isFalse);
      controller.toggleThemeMode();
      expect(controller.isDarkMode, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('jagspoor_dark_mode'), isTrue);
    });

    test('setDarkMode is idempotent (no notify on same value)', () async {
      final controller = ThemeController();
      await controller.init();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setDarkMode(false); // already false
      expect(notifications, 0);
      controller.setDarkMode(true); // change
      expect(notifications, 1);
    });

    test('notifies listeners on toggle', () async {
      final controller = ThemeController();
      await controller.init();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.toggleThemeMode();
      expect(notifications, 1);
    });

    test('lightTheme and darkTheme have correct brightness', () async {
      final controller = ThemeController();
      await controller.init();
      expect(controller.lightTheme.brightness, Brightness.light);
      expect(controller.darkTheme.brightness, Brightness.dark);
      expect(controller.materialTheme.brightness, Brightness.light);

      controller.setDarkMode(true);
      expect(controller.materialTheme.brightness, Brightness.dark);
    });

    test('palette getters reflect the official tactical spec', () async {
      final controller = ThemeController();
      await controller.init();
      // Dark mode values.
      controller.setDarkMode(true);
      expect(controller.backgroundColor, const Color(0xFF121212));
      expect(controller.cardColor, const Color(0xFF262626));
      expect(controller.accentColor, const Color(0xFFC68B59));
      expect(controller.textColor, const Color(0xFFE0E0E0));
      // Light mode values.
      controller.setDarkMode(false);
      expect(controller.backgroundColor, const Color(0xFFF4EFEA));
      expect(controller.cardColor, const Color(0xFFFFFFFF));
      expect(controller.accentColor, const Color(0xFF795548));
      expect(controller.textColor, const Color(0xFF212121));
    });

    test('AppColors constants match spec', () {
      expect(AppColors.darkBackground, const Color(0xFF121212));
      expect(AppColors.darkCard, const Color(0xFF262626));
      expect(AppColors.darkAccent, const Color(0xFFC68B59));
      expect(AppColors.darkText, const Color(0xFFE0E0E0));
      expect(AppColors.lightBackground, const Color(0xFFF4EFEA));
      expect(AppColors.lightCard, const Color(0xFFFFFFFF));
      expect(AppColors.lightAccent, const Color(0xFF795548));
      expect(AppColors.lightText, const Color(0xFF212121));
    });
  });
}
