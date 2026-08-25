import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the automated 30-day free trial + welcome
/// email Cloud Function (Task 9). The Firebase emulator cannot run in this
/// sandbox (no JVM), so these tests encode the trigger contract by parsing
/// `functions/src/user_trial_onboarding.ts` + `functions/src/index.ts` —
/// mirroring the project's established structural test pattern
/// (`payfast_itn_functions_contract_test.dart`). The compiled pure helpers
/// are additionally unit-tested in `functions/test/user_trial_onboarding.test.js`
/// (run via `npm test` in `functions/`).
void main() {
  final onboardingSource =
      File('functions/src/user_trial_onboarding.ts').readAsStringSync();
  final indexSource = File('functions/src/index.ts').readAsStringSync();
  final envExample = File('functions/.env.example').readAsStringSync();
  final packageJson = File('functions/package.json').readAsStringSync();

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

  group('welcome email dispatch', () {
    test('sends via SMTP with permanent hardcoded Brevo STARTTLS defaults', () {
      // The Brevo transport settings are permanent code defaults (NOT
      // env-overridable).
      expect(onboardingSource,
          contains('SMTP_HOST_DEFAULT = "smtp-relay.brevo.com"'));
      expect(onboardingSource, contains('SMTP_PORT_DEFAULT = 587'));
      // Port 587 is STARTTLS — the transport starts plain and upgrades to
      // TLS via STARTTLS (secure is permanently false).
      expect(onboardingSource, contains('SMTP_SECURE_DEFAULT = false'));
      expect(onboardingSource,
          contains('SMTP_FROM_DEFAULT = "admin@jag-spoor.co.za"'));
      expect(onboardingSource, contains('SMTP_FROM_NAME_DEFAULT = "JagSpoor"'));
      // Only the credentials are read from the environment — no credentials
      // are hardcoded, and no env override can move the transport off Brevo.
      expect(onboardingSource, contains('env.SMTP_USER'));
      expect(onboardingSource, contains('env.SMTP_PASS'));
      expect(onboardingSource, isNot(contains('env.SMTP_HOST')));
      expect(onboardingSource, isNot(contains('env.SMTP_PORT')));
      expect(onboardingSource, isNot(contains('env.SMTP_SECURE')));
      expect(onboardingSource, isNot(contains('env.SMTP_FROM')));
      expect(onboardingSource, contains('nodemailer.createTransport'));
      expect(onboardingSource,
          contains('auth: { user: config.user, pass: config.pass }'));
    });

    test('informs the user of the 30-day free trial + expiration date', () {
      expect(onboardingSource,
          contains('Welcome to JagSpoor — Your 30-Day Free Trial Is Active!'));
      expect(onboardingSource, contains('Your free trial expires on'));
    });

    test('email delivery is best-effort and never fails the trigger', () {
      // SMTP config missing -> skip gracefully.
      expect(onboardingSource, contains('if (!config)'));
      // No email on the user record -> skip gracefully.
      expect(onboardingSource, contains('if (!email)'));
      // Send failure is caught + logged, not rethrown.
      expect(onboardingSource,
          contains('initializeNewUserTrial: welcome email failed'));
    });

    test('SMTP environment variables are documented', () {
      // Only the credentials are env-configured; the Brevo transport settings
      // are permanent hardcoded code defaults documented in the comments.
      for (final variable in [
        'SMTP_USER',
        'SMTP_PASS',
      ]) {
        expect(envExample, contains(variable), reason: '$variable documented');
      }
      expect(envExample, contains('smtp-relay.brevo.com'));
      expect(envExample, contains('Firebase Secret'));
    });

    test('mail options carry a text alternative + standard outbound headers',
        () {
      // Deliverability contract: plain-text alternative, standard outbound
      // anti-spam headers (X-Mailer / Organization / X-Priority + a unique
      // per-message Message-ID on the jag-spoor.co.za domain), and a sender
      // that strictly matches the hardcoded SMTP_FROM_NAME_DEFAULT /
      // SMTP_FROM_DEFAULT identity.
      expect(onboardingSource, contains('text: email.text'));
      expect(onboardingSource, contains('html: email.html'));
      expect(onboardingSource, contains('OUTBOUND_MAIL_HEADERS'));
      expect(onboardingSource, contains('"X-Mailer": "JagSpoor App Engine"'));
      expect(onboardingSource, contains('"Organization": "JagSpoor"'));
      expect(onboardingSource, contains('"X-Priority": "3"'));
      expect(onboardingSource, contains('"Message-ID"'));
      expect(onboardingSource, contains('@jag-spoor.co.za>'));
      expect(onboardingSource,
          contains('from: `"\${options.config.fromName}" <\${options.config.from}>`'));
    });

    test('nodemailer is a declared functions dependency', () {
      expect(packageJson, contains('"nodemailer"'));
      expect(packageJson, contains('"@types/nodemailer"'));
    });
  });
}
