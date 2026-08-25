/// Pure, dependency-free email-verification access rules (mirrors the
/// [RoleGuard] pattern: a single testable policy object with no Firebase /
/// Flutter imports so the guard behaviour is fully unit-testable without
/// emulators).
///
/// Policy: a signed-in user whose Firebase Auth account carries an email
/// address that has NOT been verified must complete Firebase Auth's built-in
/// email-verification flow before accessing core app features (the role
/// dashboards). Users without an email address (e.g. phone-only auth) cannot
/// be email-verified and are exempt; signed-out users are exempt (they route
/// to the auth screen anyway). Google-sign-in accounts arrive from the
/// provider already verified, so the gate effectively targets email/password
/// registrations.
class EmailVerificationGuard {
  EmailVerificationGuard._();

  /// Returns `true` when the account must verify its email before proceeding.
  static bool requiresVerification({
    required bool isSignedIn,
    required bool hasEmailAddress,
    required bool emailVerified,
  }) {
    return isSignedIn && hasEmailAddress && !emailVerified;
  }

  /// The user-facing notice explaining why access is gated.
  static const String blockedMessage =
      'Please verify your email address before continuing. '
      'A verification link was sent to your inbox.';
}
