import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/auth/auth_screen.dart';
import 'package:jagspoor/features/authentication/services/auth_gate_service.dart';

/// Tests for the Google Sign-In failure-surfacing fix.
///
/// Regression guard for the audit findings:
///  1. `signInWithGoogle` previously swallowed every exception into a silent
///     `null`, which the UI treated as "user cancelled" — any real failure
///     (unregistered SHA-1 fingerprint / ApiException: 10, null idToken,
///     network) was invisible and looked like "Google Sign-In does nothing".
///  2. `_handleGoogleSignIn` had no `mounted` guards after the async gap.
void main() {
  group('GoogleSignInResult factories', () {
    test('cancelled carries no credential, no error, is not success', () {
      final result = GoogleSignInResult.cancelled();
      expect(result.cancelled, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.credential, isNull);
      expect(result.errorMessage, isNull);
    });

    test('failure carries a message and is neither success nor cancel', () {
      final result = GoogleSignInResult.failure('boom');
      expect(result.cancelled, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'boom');
    });
  });

  group('AuthGateService.friendlyGoogleSignInError', () {
    test('ApiException: 10 (DEVELOPER_ERROR) -> SHA fingerprint guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(
          code: 'sign_in_failed',
          message: 'com.google.android.gms.common.api.ApiException: 10:',
        ),
      );
      expect(message, contains('SHA-1/SHA-256'));
      expect(message, contains('Firebase Console'));
    });

    test('DEVELOPER_ERROR raw text -> SHA fingerprint guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        Exception('ApiException: 10: DEVELOPER_ERROR'),
      );
      expect(message, contains('SHA-1/SHA-256'));
    });

    test('sign_in_failed code -> SHA fingerprint guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(code: 'sign_in_failed', message: 'Sign in failed'),
      );
      expect(message, contains('SHA-1/SHA-256'));
    });

    test('no_tokens sentinel -> SHA fingerprint guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(code: 'sign_in_failed', details: 'no_tokens'),
      );
      expect(message, contains('SHA-1/SHA-256'));
    });

    test('network_error code -> network guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(code: 'network_error'),
      );
      expect(message, contains('network'));
    });

    test('raw text containing network -> network guidance', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        Exception('A network error occurred'),
      );
      expect(message, contains('network'));
    });

    test('sign_in_canceled -> cancelled message', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(code: 'sign_in_canceled'),
      );
      expect(message, contains('cancelled'));
    });

    test('generic PlatformException -> includes plugin detail', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        PlatformException(code: 'unknown_code', message: 'something odd'),
      );
      expect(message, contains('something odd'));
      expect(message, contains('Google Sign-In failed'));
    });

    test('generic non-platform error -> includes raw text', () {
      final message = AuthGateService.friendlyGoogleSignInError(
        StateError('totally unexpected'),
      );
      expect(message, contains('totally unexpected'));
      expect(message, contains('Google Sign-In failed'));
    });
  });

  group('Google Sign-In is DISABLED on all platforms', () {
    Widget buildScreen() {
      final theme = ThemeController();
      return MaterialApp(
        theme: ThemeData.light(),
        home: AuthScreen(themedata: theme),
      );
    }

    testWidgets(
      'the "Continue with Google" button is not rendered anywhere',
      (tester) async {
        await tester.pumpWidget(buildScreen());
        await tester.pumpAndSettle();

        // The button itself and its label must be gone — on every platform,
        // including the VM test host.
        expect(find.text('Continue with Google'), findsNothing);
        // No Google G logo asset either.
        expect(find.byType(SvgPicture), findsNothing);
      },
    );

    test('signInWithGoogle is a no-op that returns cancelled (never throws)',
        () async {
      final result = await AuthGateService().signInWithGoogle();
      expect(result.isSuccess, isFalse);
      expect(result.cancelled, isTrue);
      expect(result.credential, isNull);
    });

    test('reauthenticateWithGoogle is a no-op returning false', () async {
      expect(await AuthGateService().reauthenticateWithGoogle(), isFalse);
    });

    test('googleSignInEnabled is false (global kill switch)', () {
      expect(AuthGateService.googleSignInEnabled, isFalse);
    });
  });
}
