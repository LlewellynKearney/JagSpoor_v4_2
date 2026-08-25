import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/auth/screens/email_verification_screen.dart';
import 'package:jagspoor/features/auth/services/email_verification_guard.dart';
import 'package:jagspoor/features/auth/services/email_verification_service.dart';
import 'package:jagspoor/features/auth/services/password_reset_cooldown.dart';

void main() {
  setUp(() {
    EmailVerificationService.resetTestSeams();
  });

  tearDown(() {
    EmailVerificationService.resetTestSeams();
  });

  group('EmailVerificationGuard (pure policy)', () {
    test('unverified email + signed in -> requires verification', () {
      expect(
        EmailVerificationGuard.requiresVerification(
          isSignedIn: true,
          hasEmailAddress: true,
          emailVerified: false,
        ),
        isTrue,
      );
    });

    test('verified email -> not gated', () {
      expect(
        EmailVerificationGuard.requiresVerification(
          isSignedIn: true,
          hasEmailAddress: true,
          emailVerified: true,
        ),
        isFalse,
      );
    });

    test('signed-out user -> not gated (routes to auth anyway)', () {
      expect(
        EmailVerificationGuard.requiresVerification(
          isSignedIn: false,
          hasEmailAddress: true,
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('account without an email address -> exempt (phone-only auth)', () {
      expect(
        EmailVerificationGuard.requiresVerification(
          isSignedIn: true,
          hasEmailAddress: false,
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('blocked message is actionable', () {
      expect(EmailVerificationGuard.blockedMessage, contains('verify'));
    });
  });

  group('EmailVerificationStatus', () {
    test('unverified email account requires verification', () {
      const status = EmailVerificationStatus(
        isSignedIn: true,
        email: 'hunter@jag-spoor.co.za',
        emailVerified: false,
      );
      expect(status.requiresVerification, isTrue);
      expect(status.hasEmailAddress, isTrue);
    });

    test('verified account does not require verification', () {
      const status = EmailVerificationStatus(
        isSignedIn: true,
        email: 'hunter@jag-spoor.co.za',
        emailVerified: true,
      );
      expect(status.requiresVerification, isFalse);
    });

    test('blank email -> hasEmailAddress false -> not gated', () {
      const status = EmailVerificationStatus(
        isSignedIn: true,
        email: '   ',
        emailVerified: false,
      );
      expect(status.hasEmailAddress, isFalse);
      expect(status.requiresVerification, isFalse);
    });

    test('signed-out status is never gated', () {
      const status = EmailVerificationStatus(
        isSignedIn: false,
        email: '',
        emailVerified: false,
      );
      expect(status.requiresVerification, isFalse);
    });
  });

  group('EmailVerificationService (test seams)', () {
    test('currentStatus delegates to the statusResolver seam', () async {
      EmailVerificationService.statusResolverForTesting = () async =>
          const EmailVerificationStatus(
            isSignedIn: true,
            email: 'seam@test.dev',
            emailVerified: false,
          );
      final status =
          await EmailVerificationService.instance.currentStatus();
      expect(status.email, 'seam@test.dev');
      expect(status.requiresVerification, isTrue);
    });

    test('sendVerificationEmail delegates to the sender seam', () async {
      var sent = 0;
      EmailVerificationService.verificationSenderForTesting =
          () async => sent++;
      await EmailVerificationService.instance.sendVerificationEmail();
      expect(sent, 1);
    });

    test('refreshStatus delegates to the refresher seam', () async {
      EmailVerificationService.statusRefresherForTesting = () async => true;
      expect(await EmailVerificationService.instance.refreshStatus(), isTrue);
    });

    test('signOut delegates to the signOut seam', () async {
      var signedOut = 0;
      EmailVerificationService.signOutForTesting = () async => signedOut++;
      await EmailVerificationService.instance.signOut();
      expect(signedOut, 1);
    });

    test('currentStatus without Firebase resolves signed-out (no throw)',
        () async {
      final status =
          await EmailVerificationService.instance.currentStatus();
      expect(status.isSignedIn, isFalse);
      expect(status.requiresVerification, isFalse);
    });

    test('refreshStatus without Firebase returns false (no throw)', () async {
      expect(await EmailVerificationService.instance.refreshStatus(), isFalse);
    });

    test('signOut without Firebase does not throw', () async {
      await EmailVerificationService.instance.signOut();
    });
  });

  group('EmailVerificationScreen (widget)', () {
    Widget buildScreen({
      VoidCallback? onVerified,
      Future<void> Function()? sendVerificationEmailOverride,
      Future<bool> Function()? refreshVerificationStatusOverride,
      Future<void> Function()? signOutOverride,
    }) {
      return MaterialApp(
        home: EmailVerificationScreen(
          theme: ThemeController(),
          onVerified: onVerified,
          sendVerificationEmailOverride: sendVerificationEmailOverride,
          refreshVerificationStatusOverride: refreshVerificationStatusOverride,
          signOutOverride: signOutOverride,
          statusResolverOverride: () async => const EmailVerificationStatus(
            isSignedIn: true,
            email: 'hunter@jag-spoor.co.za',
            emailVerified: false,
          ),
        ),
      );
    }

    testWidgets(
        'renders the gate: title, email label, refresh + resend + sign-out actions',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emailVerificationScreen')),
          findsOneWidget);
      expect(find.text('VERIFY YOUR EMAIL'), findsOneWidget);
      expect(find.byKey(const ValueKey('verificationEmailLabel')),
          findsOneWidget);
      expect(find.text('hunter@jag-spoor.co.za'), findsOneWidget);
      expect(find.byKey(const ValueKey('refreshVerificationButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('resendVerificationButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('useDifferentAccountButton')),
          findsOneWidget);
      expect(find.textContaining('Afrihost'), findsWidgets);
    });

    testWidgets('refresh -> verified invokes the onVerified continuation',
        (tester) async {
      var continued = 0;
      await tester.pumpWidget(buildScreen(
        onVerified: () => continued++,
        refreshVerificationStatusOverride: () async => true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('refreshVerificationButton')));
      await tester.pumpAndSettle();

      expect(continued, 1);
    });

    testWidgets('refresh -> still unverified surfaces a guidance snackbar',
        (tester) async {
      var continued = 0;
      await tester.pumpWidget(buildScreen(
        onVerified: () => continued++,
        refreshVerificationStatusOverride: () async => false,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('refreshVerificationButton')));
      await tester.pumpAndSettle();

      expect(continued, 0);
      expect(find.textContaining('not verified yet'), findsOneWidget);
    });

    testWidgets(
        'resend sends the email, confirms, and engages the 60s cooldown',
        (tester) async {
      var sent = 0;
      await tester.pumpWidget(buildScreen(
        sendVerificationEmailOverride: () async => sent++,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('resendVerificationButton')));
      await tester.pump(); // start the async send
      await tester.pump(); // completion + cooldown engaged

      expect(sent, 1);
      expect(find.textContaining('Verification email sent!'), findsOneWidget);

      // Cooldown engaged: the resend button is disabled + relabelled.
      final resendButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('resendVerificationButton')),
      );
      expect(resendButton.onPressed, isNull);
      expect(find.textContaining('Resend in'), findsWidgets);

      // The countdown label reflects the shared cooldown window.
      final remaining = PasswordResetCooldown.remainingSeconds(
        now: DateTime.now(),
        until: PasswordResetCooldown.expiry(from: DateTime.now()),
      );
      expect(remaining, PasswordResetCooldown.defaultCooldownSeconds);
    });

    testWidgets('resend failure surfaces an error snackbar', (tester) async {
      await tester.pumpWidget(buildScreen(
        sendVerificationEmailOverride: () async => throw StateError('boom'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('resendVerificationButton')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Could not send the verification email'),
          findsOneWidget);
    });

    testWidgets('use-a-different-account signs out and routes to auth',
        (tester) async {
      var signedOut = 0;
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/verify',
        routes: {
          '/': (_) =>
              const Scaffold(body: Text('AUTH', key: ValueKey('authRoute'))),
          '/verify': (_) => EmailVerificationScreen(
                theme: ThemeController(),
                statusResolverOverride: () async =>
                    const EmailVerificationStatus(
                  isSignedIn: true,
                  email: 'hunter@jag-spoor.co.za',
                  emailVerified: false,
                ),
                signOutOverride: () async => signedOut++,
              ),
        },
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('useDifferentAccountButton')));
      await tester.pumpAndSettle();

      expect(signedOut, 1);
      expect(find.byKey(const ValueKey('authRoute')), findsOneWidget);
    });
  });

  group('verification gate wiring contract', () {
    // Structural source-parse contract (the established project pattern) —
    // asserts every root-routing / auth-gating surface applies the shared
    // EmailVerificationService gate before granting access to core features.
    String readSource(String relativePath) =>
        File(relativePath).readAsStringSync();

    test('auth screen routes unverified users to the verification screen',
        () {
      final source = readSource('lib/features/auth/auth_screen.dart');
      expect(source, contains('EmailVerificationService'));
      expect(source, contains('EmailVerificationScreen'));
      expect(source, contains('_requiresEmailVerification'));
      // Registration path sends the verification email.
      expect(source, contains('sendVerificationEmail'));
    });

    test('splash boot routing gates on email verification', () {
      final source = readSource('lib/core/splash_screen.dart');
      expect(source, contains('EmailVerificationService'));
      expect(source, contains('EmailVerificationScreen'));
      expect(source, contains('requiresVerification'));
    });

    test('dashboard route guard gates on email verification', () {
      final source =
          readSource('lib/features/auth/widgets/role_guarded_route.dart');
      expect(source, contains('EmailVerificationService'));
      expect(source, contains('EmailVerificationScreen'));
      expect(source, contains('requiresVerification'));
    });
  });
}
