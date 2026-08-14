import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/auth/services/password_reset_action_code_settings.dart';

void main() {
  group('PasswordResetActionCodeSettings', () {
    late ActionCodeSettings settings;

    setUp(() => settings = PasswordResetActionCodeSettings.build());

    test('uses the configured deep-link URL', () {
      expect(settings.url, 'https://jagspoor.page.link/reset-password');
    });

    test('handleCodeInApp is true', () {
      expect(settings.handleCodeInApp, isTrue);
    });

    test('pins the active Android package name', () {
      expect(settings.androidPackageName, 'com.example.jagspoor');
    });

    test('requests app install when not present (androidInstallApp: true)', () {
      expect(settings.androidInstallApp, isTrue);
    });

    test('sets a minimum Android version', () {
      expect(settings.androidMinimumVersion, isNotEmpty);
    });

    test('pins the active iOS bundle id', () {
      expect(settings.iOSBundleId, 'com.example.jagspoorV42');
    });

    test('constants are stable and documented', () {
      expect(
        PasswordResetActionCodeSettings.resetDeepLinkUrl,
        'https://jagspoor.page.link/reset-password',
      );
      expect(
        PasswordResetActionCodeSettings.androidPackageName,
        'com.example.jagspoor',
      );
      expect(
        PasswordResetActionCodeSettings.iOSBundleId,
        'com.example.jagspoorV42',
      );
    });

    test('build() returns a fresh equivalent instance each call', () {
      final a = PasswordResetActionCodeSettings.build();
      final b = PasswordResetActionCodeSettings.build();
      expect(a.url, b.url);
      expect(a.handleCodeInApp, b.handleCodeInApp);
      expect(a.iOSBundleId, b.iOSBundleId);
      expect(a.androidPackageName, b.androidPackageName);
    });

    test('asMap() round-trips all configured deep-link fields', () {
      final map = settings.asMap();
      expect(map['url'], 'https://jagspoor.page.link/reset-password');
      expect(map['handleCodeInApp'], isTrue);
      expect(map['iOS'], {'bundleId': 'com.example.jagspoorV42'});
      expect(map['android'], isA<Map>());
      final android = map['android'] as Map;
      expect(android['packageName'], 'com.example.jagspoor');
      expect(android['installApp'], isTrue);
      expect(android['minimumVersion'], '1');
    });
  });
}
