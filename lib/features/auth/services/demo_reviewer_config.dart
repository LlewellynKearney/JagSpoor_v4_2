/// Demo reviewer account configuration for the Google Play review / sandbox
/// acceptance flow.
///
/// These credentials belong to a DEDICATED REVIEW-ONLY account that is
/// provisioned in the Firebase Console (and the Google Play internal-test
/// track). They are intentionally NOT secrets:
///   * the account is given **reviewer-grade** (hunter) access only — no
///     admin claims, no financial data, no production merchant access;
///   * it is seeded with representative mock data (SAPS license applications,
///     firearm inventory, trophy room entries) on first sign-in so a reviewer
///     can showcase every restricted feature instantly;
///   * the values are centralised here so rotating the reviewed credentials
///     is a one-file change (update the console account + swap the constants).
///
/// The "Demo Reviewer Login" quick-tap button on the auth screen signs into
/// this account and seeds the demo dataset in one gesture, so Google Play
/// reviewers never have to set up an account manually.
class DemoReviewerConfig {
  DemoReviewerConfig._();

  static const String email = 'demo@jagspoor.co.za';
  static const String password = 'JagSpoorDemo2026!';

  /// Display name stamped on the demo reviewer's `users/{uid}` profile.
  static const String displayName = 'Demo Reviewer';

  /// Role granted to the review account (`hunter` — exposes the SAPS tracker,
  /// firearm inventory, trophy room, offline hunting logs, ballistics, etc.
  /// without admin / merchant surface).
  static const String role = 'hunter';

  /// Whether the demo account is enabled. Flip to `false` to disable the
  /// in-app demo entry entirely (e.g. for a production roll-out where the
  /// review account has been retired).
  static const bool enabled = true;

  /// Human-readable context used in the auth-screen snackbar after a
  /// successful demo sign-in.
  static const String label = 'Demo Reviewer';
}