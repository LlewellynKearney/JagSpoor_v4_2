import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the automated 30-day free trial Cloud
/// Function (Task 9). The Firebase emulator cannot run in this sandbox (no
/// JVM), so these tests encode the trigger contract by parsing
/// `functions/src/user_trial_onboarding.ts` + `functions/src/index.ts` —
/// mirroring the project's established structural test pattern
/// (the PayFast billing integration has been removed from the functions).
/// The compiled pure helpers
/// are additionally unit-tested in `functions/test/user_trial_onboarding.test.js`
/// (run via `npm test` in `functions/`).
void main() {
  final onboardingSource =
      File('functions/src/user_trial_onboarding.ts').readAsStringSync();
  final indexSource = File('functions/src/index.ts').readAsStringSync();

  group('initializeNewUserTrial auth trigger', () {
    test('is exported from the functions entry point', () {
      expect(indexSource,
          contains('export { initializeNewUserTrial } from "./user_trial_onboarding"'));
    });

    test('is a Firebase Auth user-creation trigger in us-central1', () {
      // v1 auth provider: .auth.user().onCreate(...)
      expect(onboardingSource, contains('.auth.user()'));
      expect(onboardingSource, contains('.onCreate(async (user)'));
      expect(onboardingSource, contains('.region("us-central1")'));
      expect(onboardingSource, contains('export const initializeNewUserTrial'));
    });

    test('initializes new users to a 30-day free trial', () {
      // Exactly 30 days.
      expect(onboardingSource, contains('export const TRIAL_PERIOD_DAYS = 30'));
      expect(onboardingSource,
          contains('TRIAL_PERIOD_DAYS * 24 * 60 * 60 * 1000'));
      // Firestore profile initialization contract.
      expect(onboardingSource, contains('subscriptionStatus: "trialing"'));
      expect(onboardingSource, contains('trialEndsAt'));
      expect(onboardingSource, contains('requiresPayment: false'));
      expect(onboardingSource,
          contains('firestore().collection("users").doc(uid)'));
    });

    test('merge-writes the trial state without clobbering a non-trial status',
        () {
      expect(onboardingSource, contains('{ merge: true }'));
      // An existing non-trial subscriptionStatus is preserved (no downgrade).
      expect(onboardingSource,
          contains('existingStatus !== "" && existingStatus !== "trialing"'));
    });
  });

  group('no welcome-email or trial-abuse surface remains', () {
    test('the onboarding module carries no SMTP / nodemailer transport', () {
      expect(onboardingSource, isNot(contains('nodemailer')));
      expect(onboardingSource, isNot(contains('SMTP')));
      expect(onboardingSource, isNot(contains('sendWelcomeEmail')));
      expect(onboardingSource, isNot(contains('buildWelcomeEmail')));
      expect(onboardingSource, isNot(contains('OUTBOUND_MAIL_HEADERS')));
    });

    test('the onboarding module carries no device-fingerprint abuse check',
        () {
      expect(onboardingSource, isNot(contains('deviceFingerprint')));
      expect(onboardingSource, isNot(contains('resolveDeviceFingerprint')));
      expect(onboardingSource, isNot(contains('isTrialAbuseExempt')));
      expect(onboardingSource, isNot(contains('trialBlockedReason')));
      expect(onboardingSource, isNot(contains('TRIAL_ABUSE_EXEMPT_EMAILS')));
    });
  });
}
