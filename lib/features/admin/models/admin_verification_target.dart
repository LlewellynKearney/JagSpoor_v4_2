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
/// [AdminVerificationTarget.missedVerification] is the predicate the
/// "Resend to All Unverified" bulk action filters on: the account is
/// unverified AND its last recorded send either never happened or failed.
class AdminVerificationTarget {
  final String uid;
  final String email;

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
    this.emailVerified = false,
    this.verificationEmailSent = false,
    this.verificationEmailLastError,
    this.verificationEmailLastAttemptAt,
  });

  /// Whether the account missed (or never received) its verification email:
  /// it is unverified AND no successful dispatch is on record.
  bool get missedVerification =>
      !emailVerified && !verificationEmailSent;

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
      emailVerified: _bool(d['emailVerified']),
      verificationEmailSent: _bool(d['verificationEmailSent']),
      verificationEmailLastError: err.isEmpty ? null : err,
      verificationEmailLastAttemptAt:
          _date(d['verificationEmailLastAttemptAt']),
    );
  }

  /// Filters [targets] to the accounts that missed their verification email.
  static List<AdminVerificationTarget> missedUsers(
    Iterable<AdminVerificationTarget> targets,
  ) =>
      targets.where((t) => t.missedVerification).toList(growable: false);
}

/// The maximum number of accounts a single "Resend to All Unverified" batch
/// may address.
///
/// Resending is a network-bound operation against Firebase Auth; an unbounded
/// batch could exhaust the Auth / SMTP quota and get the project throttled.
/// The bulk action therefore processes at most this many accounts per run and
/// reports how many remain, so the admin can re-run to drain a larger list.
const int kAdminVerificationResendBatchLimit = 50;

/// Selects the next batch of accounts to resend to, capped at [limit].
///
/// Pure so the batching contract is unit-testable without Firestore.
List<AdminVerificationTarget> adminVerificationResendBatch(
  Iterable<AdminVerificationTarget> targets, {
  int limit = kAdminVerificationResendBatchLimit,
}) {
  final missed = AdminVerificationTarget.missedUsers(targets);
  if (missed.length <= limit) return missed;
  return missed.sublist(0, limit);
}
