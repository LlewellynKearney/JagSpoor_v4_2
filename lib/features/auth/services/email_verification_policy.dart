import 'demo_reviewer_config.dart';

/// Pure, dependency-free policy for the email-verification gate (TODO #3).
///
/// Keeps the "must this account verify its inbox before reaching a dashboard?"
/// decision in one testable place so every entry point — registration, email
/// login, Google sign-in, 2FA completion and cold-launch splash routing —
/// agrees on the rule. No Firebase / Flutter imports, so it is fully
/// unit-testable without a Firebase app.
///
/// A signed-in account with an email address that has NOT been verified is
/// gated. Phone-only accounts (no email) are exempt because there is nothing
/// to verify, and two pre-provisioned **system** accounts are deliberately
/// exempt:
///  * the platform admin allow-list ([adminEmail]), and
///  * the Google Play demo-reviewer account ([DemoReviewerConfig.email]).
///
/// Both are provisioned directly in the Firebase Console; gating them would
/// lock the operator out of the platform and break the Play Store review flow.
class EmailVerificationPolicy {
  EmailVerificationPolicy._();

  /// The platform admin allow-list. Mirrors the lists used by
  /// `UserRoleProvider` / `TrialAssignmentPolicy` so admin detection agrees
  /// across the app.
  static const Set<String> adminEmails = {
    'admin@jag-spoor.co.za',
  };

  /// Emails that never require verification (system / review accounts).
  static Set<String> get exemptEmails => {
        ...adminEmails,
        DemoReviewerConfig.email,
      };

  /// Whether [email] belongs to an exempt (system / review) account.
  /// Case-insensitive + trimmed; null / blank is not exempt.
  static bool isExemptEmail(String? email) {
    final normalized = email?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return exemptEmails
        .map((e) => e.trim().toLowerCase())
        .contains(normalized);
  }

  /// Whether the account must verify its email before it may reach a
  /// dashboard.
  ///
  /// Gated only when the account is signed in, HAS an email address, that
  /// address is unverified, and the account is not an exempt system / review
  /// account.
  static bool requiresVerification({
    required String? email,
    required bool emailVerified,
  }) {
    final normalized = email?.trim() ?? '';
    if (normalized.isEmpty) return false;
    if (emailVerified) return false;
    if (isExemptEmail(normalized)) return false;
    return true;
  }
}
