// Tests for the TODO #3 email-verification enforcement.
//
// Covers:
//  * the pure gate policy (`EmailVerificationPolicy`);
//  * the `EmailVerificationService` API contract;
//  * the `EmailVerificationScreen` widget: render, manual "I've verified",
//    resend + 60-second cooldown, auto-check poll, sign-out, and the
//    no-Firebase fallbacks;
//  * the structural wiring in `auth_screen.dart` / `splash_screen.dart`
//    (registration + sign-in + cold-launch all gate on `emailVerified`).
//
// The Firebase emulator cannot run in this sandbox, so the wiring is asserted
// structurally against the source, mirroring the project's established
// contract-test pattern.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/screens/email_verification_screen.dart';
import 'package:jagspoor/features/auth/services/email_verification_policy.dart';
import 'package:jagspoor/features/auth/services/email_verification_service.dart';

void main() {
  group('EmailVerificationPolicy', () {
    test('an unverified email address requires verification', () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: 'hunter@example.com',
          emailVerified: false,
        ),
        isTrue,
      );
    });

    test('a verified email address never requires verification', () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: 'hunter@example.com',
          emailVerified: true,
        ),
        isFalse,
      );
    });

    test('a phone-only account (no email) is exempt', () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: null,
          emailVerified: false,
        ),
        isFalse,
      );
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: '   ',
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('the platform admin account is exempt', () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: 'admin@jag-spoor.co.za',
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('the demo-reviewer account is exempt (Play review must not lock out)',
        () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: 'demo@jagspoor.co.za',
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('exemption is case-insensitive and trims surrounding whitespace', () {
      expect(
        EmailVerificationPolicy.isExemptEmail('  ADMIN@Jag-Spoor.co.za '),
        isTrue,
      );
      expect(
        EmailVerificationPolicy.isExemptEmail('unknown@example.com'),
        isFalse,
      );
      expect(EmailVerificationPolicy.isExemptEmail(null), isFalse);
      expect(EmailVerificationPolicy.isExemptEmail(''), isFalse);
    });

    test('a verified exempt account is still not gated', () {
      expect(
        EmailVerificationPolicy.requiresVerification(
          email: 'demo@jagspoor.co.za',
          emailVerified: true,
        ),
        isFalse,
      );
    });
  });

  group('EmailVerificationService', () {
    test('exposes the requested send/check API', () {
      expect(EmailVerificationService.instance, isNotNull);
      // The signatures must match the task contract.
      expect(
        EmailVerificationService.instance.sendVerificationEmail,
        isA<Future<void> Function()>(),
      );
      expect(
        EmailVerificationService.instance.checkVerified,
        isA<Future<bool> Function()>(),
      );
    });

    test('without a Firebase app it degrades gracefully (no throw)', () async {
      // No Firebase.initializeApp in the test runner -> [core/no-app]; the
      // service must resolve to a safe default rather than throw.
      expect(EmailVerificationService.instance.currentUser, isNull);
      await EmailVerificationService.instance.sendVerificationEmail();
      expect(await EmailVerificationService.instance.checkVerified(), isFalse);
    });
  });

  group('EmailVerificationScreen (widget)', () {
    Widget buildScreen({
      required VoidCallback onVerified,
      String? email = 'hunter@example.com',
      Future<void> Function()? send,
      Future<bool> Function()? refresh,
      Future<void> Function()? signOut,
    }) {
      return MaterialApp(
        theme: ThemeData.light(),
        home: EmailVerificationScreen(
          onVerified: onVerified,
          emailOverride: email,
          sendVerificationEmailOverride: send,
          refreshVerificationStatusOverride: refresh,
          signOutOverride: signOut,
        ),
      );
    }

    testWidgets('renders the explanation + the target email address',
        (tester) async {
      await tester.pumpWidget(buildScreen(onVerified: () {}));
      await tester.pump();

      expect(find.text('Verify your email'), findsWidgets);
      expect(
        find.text('We sent verification to hunter@example.com'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('iHaveVerifiedButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('resendVerificationButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('useDifferentAccountButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('openEmailAppHint')), findsOneWidget);

      // The periodic auto-check timer must be cancelled on dispose.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("'I've verified' continues when the status reports verified",
        (tester) async {
      var continued = false;
      await tester.pumpWidget(buildScreen(
        onVerified: () => continued = true,
        refresh: () async => true,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('iHaveVerifiedButton')));
      await tester.pump();

      expect(continued, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("'I've verified' stays put with guidance when unverified",
        (tester) async {
      var continued = false;
      await tester.pumpWidget(buildScreen(
        onVerified: () => continued = true,
        refresh: () async => false,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('iHaveVerifiedButton')));
      await tester.pump();

      expect(continued, isFalse);
      expect(
        find.textContaining('could not confirm your verification'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('resend dispatches the email and starts a 60s cooldown',
        (tester) async {
      var sends = 0;
      await tester.pumpWidget(buildScreen(
        onVerified: () {},
        send: () async => sends++,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('resendVerificationButton')));
      await tester.pump();

      expect(sends, 1);
      expect(
        find.textContaining('Verification email sent to hunter@example.com'),
        findsOneWidget,
      );
      // The button relabels to the live countdown and disables itself.
      expect(find.textContaining('RESEND IN '), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('resendVerificationButton')),
      );
      expect(button.onPressed, isNull,
          reason: 'The resend button must be disabled while cooling down.');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('auto-check poll continues the flow when verification lands',
        (tester) async {
      var continued = false;
      await tester.pumpWidget(buildScreen(
        onVerified: () => continued = true,
        refresh: () async => true,
      ));
      await tester.pump();

      // The 3-second periodic timer triggers the automatic check.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(continued, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sign-out returns to the auth screen (route "/")',
        (tester) async {
      var signedOut = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        initialRoute: '/verify',
        routes: {
          '/': (_) => const Scaffold(body: Text('AUTH_SCREEN')),
          '/verify': (_) => EmailVerificationScreen(
                onVerified: () {},
                emailOverride: 'hunter@example.com',
                signOutOverride: () async => signedOut = true,
              ),
        },
      ));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('useDifferentAccountButton')),
      );
      await tester.pumpAndSettle();

      expect(signedOut, isTrue);
      expect(find.text('AUTH_SCREEN'), findsOneWidget);
    });

    testWidgets('renders without Firebase (no [core/no-app] crash)',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        onVerified: () {},
        email: null, // force the live Firebase lookup path
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('We sent verification to'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Email-verification enforcement wiring (structural contract)', () {
    final authSource =
        File('lib/features/auth/auth_screen.dart').readAsStringSync();
    final splashSource =
        File('lib/core/splash_screen.dart').readAsStringSync();
    final policySource = File(
      'lib/features/auth/services/email_verification_policy.dart',
    ).readAsStringSync();
    final guardSource = File(
      'lib/features/auth/widgets/role_guarded_route.dart',
    ).readAsStringSync();

    test('registration sends the verification email after account creation',
        () {
      final createIdx = authSource.indexOf('createUserWithEmailAndPassword(');
      final sendIdx =
          authSource.indexOf('sendVerificationEmail()', createIdx);
      expect(createIdx, greaterThan(-1));
      expect(sendIdx, greaterThan(createIdx),
          reason: 'signUp must dispatch the verification email after '
              'createUserWithEmailAndPassword.');
    });

    test('registration routes to the verification gate (not the dashboard)',
        () {
      // The registration success path pushes the gate.
      expect(authSource, contains('_pushEmailVerification()'));
    });

    test('auth routing gates on email verification before role routing', () {
      final gateIdx = authSource.indexOf('_emailVerificationRequired()');
      final roleIdx =
          authSource.indexOf('resolveRole(forceRefresh: true)', gateIdx);
      expect(gateIdx, greaterThan(-1));
      expect(roleIdx, greaterThan(gateIdx),
          reason: 'The verification gate must run before role resolution so '
              'an unverified account never reaches a dashboard.');
    });

    test('the splash screen gates boot routing on email verification', () {
      expect(splashSource,
          contains('EmailVerificationPolicy.requiresVerification('));
      expect(splashSource, contains('EmailVerificationScreen('));
      final gateIdx =
          splashSource.indexOf('EmailVerificationPolicy.requiresVerification(');
      final roleIdx =
          splashSource.indexOf('resolveRole(forceRefresh: true)', gateIdx);
      expect(roleIdx, greaterThan(gateIdx));
    });

    test('the policy exempts the admin + demo-reviewer accounts', () {
      expect(policySource, contains("'admin@jag-spoor.co.za'"));
      expect(policySource, contains('DemoReviewerConfig.email'));
      expect(policySource, contains('requiresVerification'));
    });

    test('the route guard re-checks verification (deep-link defense)', () {
      expect(guardSource,
          contains('EmailVerificationPolicy.requiresVerification('));
      expect(guardSource, contains('EmailVerificationScreen('));
    });
  });
}
