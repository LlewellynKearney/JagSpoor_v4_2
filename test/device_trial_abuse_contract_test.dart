import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the device-level trial-abuse prevention
/// flow (Task 11). The Firebase emulator cannot run in this sandbox, so
/// these tests encode the end-to-end contract structurally, mirroring the
/// project's established pattern (`welcome_email_functions_contract_test`).
///
/// Paths covered:
///  - client registration wires `deviceFingerprint` into `users/{uid}`
///    (email/password + Google sign-in);
///  - `initializeNewUserTrial` Cloud Function gates the trial with the
///    fail-closed device check (blocked on missing/duplicate/check-error);
///  - `firestore.rules` freezes `deviceFingerprint` once set (immutability).
void main() {
  final authScreenSource =
      File('lib/features/auth/auth_screen.dart').readAsStringSync();
  final serviceSource =
      File('lib/features/auth/services/device_fingerprint_service.dart')
          .readAsStringSync();
  final onboardingSource =
      File('functions/src/user_trial_onboarding.ts').readAsStringSync();
  final rulesSource = File('firestore.rules').readAsStringSync();

  group('client registration stamps the hardware fingerprint', () {
    test('the DeviceFingerprintService is wired into the auth screen', () {
      expect(authScreenSource,
          contains("import 'services/device_fingerprint_service.dart'"));
      expect(authScreenSource,
          contains('DeviceFingerprintService.instance'));
    });

    test('registration computes the fingerprint before account creation',
        () {
      expect(authScreenSource, contains('deviceFingerprint'));
      expect(authScreenSource, contains('computeFingerprint()'));
    });

    test('the initial users doc write carries `deviceFingerprint`', () {
      expect(authScreenSource, contains("'deviceFingerprint': deviceFingerprint"));
    });

    test('Google sign-in stamps the fingerprint on first sign-in', () {
      expect(authScreenSource, contains('_stampDeviceFingerprint'));
      expect(authScreenSource, contains('stampDeviceFingerprint(user.uid)'));
    });
  });

  group('DeviceFingerprintService', () {
    test('computes a SHA-256 of the platform hardware identifier', () {
      expect(serviceSource, contains('sha256.convert(utf8.encode(raw))'));
      expect(serviceSource, contains('Platform.isAndroid'));
      expect(serviceSource, contains('Platform.isIOS'));
      // Android: Settings.Secure.ANDROID_ID; iOS: identifierForVendor.
      expect(serviceSource, contains('info.id'));
      expect(serviceSource, contains('info.identifierForVendor'));
    });

    test('stamps via a Firestore merge-write on users/{uid}', () {
      expect(serviceSource, contains("collection('users').doc(userId)"));
      expect(serviceSource, contains('SetOptions(merge: true)'));
      expect(serviceSource, contains('stampWriterForTesting'));
    });

    test('exposes static test seams + reset helper', () {
      expect(serviceSource, contains('fingerprintResolverForTesting'));
      expect(serviceSource, contains('resetTestSeams()'));
      expect(serviceSource, contains('currentFingerprint()'));
    });
  });

  group('backend fail-closed trial check', () {
    test('resolveDeviceFingerprint polls until the client stamp lands', () {
      expect(onboardingSource,
          contains('export async function resolveDeviceFingerprint'));
      expect(onboardingSource, contains('await sleep(interval)'));
      expect(onboardingSource,
          contains('export const FINGERPRINT_POLL_TIMEOUT_MS = 15000'));
    });

    test('duplicate check excludes the self uid', () {
      expect(onboardingSource,
          contains('export async function otherUserHasDeviceFingerprint'));
      expect(onboardingSource, contains('doc.id !== excludeUid'));
      expect(onboardingSource,
          contains('.where("deviceFingerprint", "==", fingerprint)'));
    });

    test('blocked accounts write a fail-closed state', () {
      expect(onboardingSource, contains('subscriptionStatus: "blocked"'));
      expect(onboardingSource, contains('requiresPayment: true'));
      expect(onboardingSource, contains('trialBlockedReason'));
    });

    test('missing fingerprint / duplicate / check error all block (fail-closed)', () {
      expect(onboardingSource,
          contains('TRIAL_BLOCK_REASON_UNSET'));
      expect(onboardingSource,
          contains('TRIAL_BLOCK_REASON_DUPLICATE'));
      expect(onboardingSource,
          contains('TRIAL_BLOCK_REASON_ERROR'));
    });

    test('blocked accounts skip the welcome email', () {
      expect(onboardingSource,
          contains('Blocked accounts get no welcome email'));
    });
  });

  group('firestore.rules freeze the fingerprint once set', () {
    test('users update is denied when the fingerprint would change', () {
      expect(rulesSource,
          contains("'deviceFingerprint' in resource.data"));
      expect(rulesSource,
          contains('resource.data.deviceFingerprint == '
              'request.resource.data.deviceFingerprint'));
    });

    test('users write is owner-scoped signed-in (covers create + update), '
        'with a resource-null create guard', () {
      expect(rulesSource,
          contains('match /users/{userId}'));
      expect(rulesSource,
          contains('allow write: if isSignedIn() && request.auth.uid == userId'));
      expect(rulesSource, contains('resource == null'));
    });
  });
}
