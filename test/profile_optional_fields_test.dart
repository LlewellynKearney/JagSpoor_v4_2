import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/hunter_dashboard.dart';

/// Task 1B (2026-11-13): Hunter profile fields made OPTIONAL.
///
/// Verifies the fix end-to-end without the Firestore emulator (which cannot
/// run in this sandbox — see AGENTS.md environment constraints):
///  1. The Hunter Profile form no longer carries required validators for
///     First Name / Surname / Phone, and the email field keeps ONLY the
///     format check (empty is allowed).
///  2. The Save payload still writes `firstName` / `lastName` / `phone` /
///     `email` (no field deleted, no key renamed).
///  3. The 4 onboarding-gate redirects are gone — no call site pushes the
///     Hunter Profile screen with `pushAndRemoveUntil`, so a hunter with an
///     empty profile is never bounced back.
///  4. A hunter reaches the dashboard with an empty profile (no redirect
///     loop) — the dashboard renders.
///
/// See `docs/fix-profile-optional-fields/AUDIT.md`.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('Hunter Profile form — required validators removed', () {
    late String screen;

    setUpAll(() {
      screen = read('lib/features/hunter_mode/hunter_profile_screen.dart');
    });

    test('no required validators for first name / surname / phone', () {
      expect(screen, isNot(contains('First name is required')));
      expect(screen, isNot(contains('Surname is required')));
      expect(screen, isNot(contains('Enter a phone number or an email')));
      expect(screen, isNot(contains('Enter an email or a phone number')));
    });

    test('the email field keeps ONLY the format validator', () {
      expect(screen, contains('Enter a valid email address'));
      // The paired "email OR phone" requirement is gone: the format check
      // only fires when the field is non-empty.
      expect(screen, contains('if (email.isNotEmpty &&'));
    });

    test('labels drop the mandatory asterisk and mark the fields optional',
        () {
      expect(screen, contains("'First Name'"));
      expect(screen, contains("'Surname'"));
      expect(screen, contains("'Phone Number (optional)'"));
      expect(screen, contains("'Email Address (optional)'"));
      expect(screen, isNot(contains("'First Name *'")));
      expect(screen, isNot(contains("'Surname *'")));
      expect(screen, isNot(contains("'Phone Number *'")));
      expect(screen, isNot(contains("'Email Address *'")));
    });

    test('the section header drops the mandatory asterisk', () {
      expect(screen, contains("_buildSectionHeader('CONTACT INFORMATION')"));
      expect(
        screen,
        isNot(contains("_buildSectionHeader('CONTACT INFORMATION *')")),
      );
    });

    test('the "mandatory / cannot use the app" helper copy is gone', () {
      expect(screen, isNot(contains('are mandatory. You cannot use the app')));
    });

    test('Save still writes all four Firestore keys (no data loss)', () {
      expect(screen, contains("'firstName': first,"));
      expect(screen, contains("'lastName': last,"));
      expect(screen, contains("'phone': _phoneController.text.trim(),"));
      expect(screen, contains("'email': _emailController.text.trim(),"));
    });

    test('the Save method still runs the form validate() gate', () {
      // validate() now only guards the email-format check; it passes on empty.
      expect(screen, contains('_formKey.currentState!.validate()'));
    });
  });

  group('Onboarding-gate redirects removed from all 4 call sites', () {
    test('auth_screen no longer redirects to the profile screen', () {
      final src = read('lib/features/auth/auth_screen.dart');
      // No live code references the gate or the profile screen (the only
      // remaining mentions are the explanatory Task 1B comments).
      expect(src, isNot(contains('HunterProfileScreen(')));
      expect(src, isNot(contains('HunterProfileCompleteness.instance')));
      expect(src, isNot(contains('statusFor(')));
      expect(
        src,
        isNot(contains('complete your profile before continuing')),
      );
    });

    test('splash_screen no longer redirects to the profile screen', () {
      final src = read('lib/core/splash_screen.dart');
      expect(src, isNot(contains('HunterProfileScreen(')));
      expect(src, isNot(contains('HunterProfileCompleteness.instance')));
      expect(src, isNot(contains('statusFor(')));
    });

    test('role_selection_screen no longer redirects to the profile screen',
        () {
      final src = read('lib/features/auth/role_selection_screen.dart');
      expect(src, isNot(contains('HunterProfileScreen(')));
      expect(src, isNot(contains('HunterProfileCompleteness.instance')));
      expect(src, isNot(contains('statusFor(')));
    });

    test('hunter_dashboard no longer redirects to the profile screen', () {
      final src = read('lib/features/hunter_mode/hunter_dashboard.dart');
      // The one-shot redirect guard field is gone and the defense-in-depth
      // helper is an empty no-op (its redirect body was removed).
      expect(src, isNot(contains('_onboardingRedirected')));
      expect(
        src,
        contains('Future<void> _enforceProfileOnboarding() async {}'),
        reason: 'The redirect body must be gone (no-op retained only for '
            'the initState call site).',
      );
      expect(src, isNot(contains('HunterProfileCompleteness.instance')));
      expect(src, isNot(contains('statusFor(')));
    });
  });

  group('Hunter reaches the dashboard with an empty profile (no bounce)', () {
    testWidgets('the dashboard renders without a profile redirect',
        (tester) async {
      // A hunter with no firstName / lastName / phone / email (and no
      // Firebase app in the test env) must still land on the dashboard —
      // the removed redirect must not fire.
      await tester.pumpWidget(
        MaterialApp(home: HunterDashboard(theme: ThemeController.instance)),
      );
      await tester.pump();

      expect(find.text('JAGSPOOR'), findsOneWidget);
      expect(find.text('HUNTER MODE'), findsOneWidget);
      expect(find.text('TACTICAL MODULES'), findsOneWidget);
      // No forced navigation to the Hunter Profile screen.
      expect(find.text('SAVE PROFILE'), findsNothing);
    });
  });
}
