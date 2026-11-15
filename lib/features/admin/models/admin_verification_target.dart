/// Email-verification status tracking for the Admin Portal V2.
///
/// The admin portal reads Firestore (`users`), never the Auth user list, so it
/// cannot see Firebase Auth's `emailVerified` flag directly. Two signals are
/// used to decide whether an account still needs a verification email:
///
///   * [AdminUserRecord.emailVerified] — mirrored onto `users/{uid}` by the
///     app (`EmailVerificationService.checkVerified` / the gate). Missing on
///     legacy documents (defaults to `false`, i.e. "assume unverified").
///   * [verificationEmailSent] / [verificationEmailLastError] /
///     [verificationEmailLastAttemptAt] — the audit trail the client writes
///     when it dispatches (or fails to dispatch) a verification email.
///
/// [AdminVerificationTarget.missedVerification] is the RAW unverified predicate
/// (unverified AND no successful send). It OVER-COUNTS the true resend targets:
/// role selection in JagSpoor does NOT require a verified email, so a
/// role-bearing account demonstrably got into the app and just never clicked
/// the link. The unverified set is therefore split into two buckets:
///
///   * [AdminVerificationTarget.missedNoRole] — BUCKET 2: unverified AND no
///     role. Never completed signup → likely never got the email → the resend
///     targets.
///   * [AdminVerificationTarget.unverifiedWithRole] — BUCKET 1: unverified but
///     has a role. An active user who received the email and never clicked →
///     reminder only, NEVER bulk re-sent (that would spam active users).
class AdminVerificationTarget {
  final String uid;
  final String email;

  /// The account's operational role (`users/{uid}.role`). Blank / `none` /
  /// `unassigned` / `unknown` mean the account never finished role selection.
  final String role;

  /// Whether the account's email is verified (mirrored from Auth). Missing /
  /// non-`true` values count as unverified.
  final bool emailVerified;

  /// Whether a verification email was last confirmed dispatched. `false` when
  /// the field is missing (legacy account) or explicitly false.
  final bool verificationEmailSent;

  /// The last recorded failure reason, or null when the last attempt succeeded
  /// (or no attempt was recorded).
  final String? verificationEmailLastError;

  /// When the last dispatch attempt happened, or null when unknown.
  final DateTime? verificationEmailLastAttemptAt;

  const AdminVerificationTarget({
    required this.uid,
    this.email = '',
    this.role = '',
    this.emailVerified = false,
    this.verificationEmailSent = false,
    this.verificationEmailLastError,
    this.verificationEmailLastAttemptAt,
  });

  /// Role values that mean "no operational role was selected yet".
  static const List<String> noRoleValues = [
    '',
    'none',
    'unassigned',
    'unknown',
  ];

  /// Whether the account has a REAL (operational) role. Role selection does
  /// NOT require a verified email, so a role-bearing account demonstrably got
  /// into the app — it received the email (or bypassed the gate) and simply
  /// never clicked. Those accounts must NOT be bulk re-sent to.
  bool get hasRole => !noRoleValues.contains(role.trim().toLowerCase());

  /// Whether the account missed (or never received) its verification email:
  /// it is unverified AND no successful dispatch is on record.
  bool get missedVerification => !emailVerified && !verificationEmailSent;

  /// BUCKET 2 — unverified AND no role: never completed signup, likely never
  /// got the email. These are the resend targets.
  bool get missedNoRole => missedVerification && !hasRole;

  /// BUCKET 1 — unverified WITH a role: an active user who never clicked the
  /// link. Reminder only; never bulk re-sent.
  bool get unverifiedWithRole => missedVerification && hasRole;

  /// Whether the last recorded dispatch FAILED (an error is on record).
  bool get lastAttemptFailed =>
      (verificationEmailLastError ?? '').trim().isNotEmpty;

  /// A short admin-facing label for the row's status cell.
  String get statusLabel {
    if (emailVerified) return 'Verified';
    if (verificationEmailSent) return 'Sent';
    if (lastAttemptFailed) return 'Failed';
    return 'Never sent';
  }

  static bool _bool(Object? value) => value == true;

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      // Firestore Timestamp exposes `toDate()`; avoid importing the type here
      // so the model stays pure and unit-testable without Firestore.
      final dynamic v = value;
      final dynamic converted = v.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      /* not a Timestamp */
    }
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  /// Parses a `users/{uid}` document into the verification snapshot.
  factory AdminVerificationTarget.fromMap(String uid, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final err = (d['verificationEmailLastError'] ?? '').toString().trim();
    return AdminVerificationTarget(
      uid: uid,
      email: (d['email'] ?? '').toString().trim().toLowerCase(),
      role: (d['role'] ?? '').toString().trim(),
      emailVerified: _bool(d['emailVerified']),
      verificationEmailSent: _bool(d['verificationEmailSent']),
      verificationEmailLastError: err.isEmpty ? null : err,
      verificationEmailLastAttemptAt:
          _date(d['verificationEmailLastAttemptAt']),
    );
  }

  /// Filters [targets] to the raw unverified set (unverified AND no successful
  /// send). NOTE: this OVER-COUNTS the resend targets — prefer
  /// [noRoleUsers] / [withRoleUsers].
  static List<AdminVerificationTarget> missedUsers(
    Iterable<AdminVerificationTarget> targets,
  ) =>
      targets.where((t) => t.missedVerification).toList(growable: false);

  /// BUCKET 2 — unverified AND no role: the resend targets.
  static List<AdminVerificationTarget> noRoleUsers(
    Iterable<AdminVerificationTarget> targets,
  ) =>
      targets.where((t) => t.missedNoRole).toList(growable: false);

  /// BUCKET 1 — unverified but has a role: reminder only, never bulk re-sent.
  static List<AdminVerificationTarget> withRoleUsers(
    Iterable<AdminVerificationTarget> targets,
  ) =>
      targets.where((t) => t.unverifiedWithRole).toList(growable: false);
}

/// The maximum number of accounts a single bulk resend may address.
///
/// Resending is a network-bound operation against Firebase Auth; an unbounded
/// batch could exhaust the Auth / SMTP quota and get the project throttled.
/// The bulk action therefore processes at most this many accounts per run and
/// reports how many remain, so the admin can re-run to drain a larger list.
const int kAdminVerificationResendBatchLimit = 50;

/// Selects the next batch of accounts to resend to, capped at [limit].
///
/// Only the NO-ROLE bucket is eligible — role-bearing accounts are never bulk
/// re-sent (they are active users who simply never clicked the link). Pure so
/// the batching contract is unit-testable without Firestore.
List<AdminVerificationTarget> adminVerificationResendBatch(
  Iterable<AdminVerificationTarget> targets, {
  int limit = kAdminVerificationResendBatchLimit,
}) {
  final missed = AdminVerificationTarget.noRoleUsers(targets);
  if (missed.length <= limit) return missed;
  return missed.sublist(0, limit);
}
