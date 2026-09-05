/// Demo reviewer account configuration for the Google Play review / sandbox
/// acceptance flow.
///
/// These credentials belong to a DEDICATED REVIEW-ONLY account that is
/// provisioned in the Firebase Console (and the Google Play internal-test
/// track). They are intentionally NOT secrets:
///   * the account is given **reviewer-grade DUAL access** (hunter +
///     outfitter) — no admin claims, no financial data, no production
///     merchant access;
///   * it is seeded with representative mock data on first sign-in — SAPS
///     license applications, firearm inventory, trophy room entries, offline
///     harvest logs AND the full outfitter showcase (farms, trophy stock,
///     published packages, price lists, service rates, client bookings) — so
///     a reviewer can showcase every restricted feature instantly and toggle
///     seamlessly between the Hunter and Outfitter dashboards;
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

  /// Primary role field stamped on the review account's `users/{uid}` doc.
  /// `dual` marks the account as BOTH hunter and outfitter so the reviewer
  /// is admitted to both dashboards (see `UserRoleProvider.resolveRole`).
  /// The doc also carries `isDualRole: true` + `roles: ['hunter','outfitter']`
  /// as explicit, downstream-readable signals.
  static const String role = 'dual';

  /// Explicit role-set signal persisted alongside [role] so any consumer
  /// reads a self-describing access grant.
  static const List<String> roles = ['hunter', 'outfitter'];

  /// The billing tier displayed on the demo reviewer's subscription — hunter
  /// tier is the cheaper of the two, and the demo has an ACTIVE entitlement
  /// so neither paywall surface blocks a reviewer.
  static const String subscriptionTier = 'hunter';

  /// Whether the demo account is enabled. Flip to `false` to disable the
  /// in-app demo entry entirely (e.g. for a production roll-out where the
  /// review account has been retired).
  static const bool enabled = true;

  /// Human-readable context used in the auth-screen snackbar after a
  /// successful demo sign-in.
  static const String label = 'Demo Reviewer';
}