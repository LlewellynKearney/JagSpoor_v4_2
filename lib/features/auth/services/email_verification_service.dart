import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Email-verification service (TODO #3).
///
/// A thin, null-safe wrapper over Firebase Auth's built-in verification flow.
/// The repository has no `lib/services/auth_service.dart`; the auth surfaces
/// live in `lib/features/authentication/services/auth_gate_service.dart`
/// (Google / 2FA) and here (email verification), so this is the equivalent
/// home for the requested API:
///
/// ```dart
/// await EmailVerificationService.instance.sendVerificationEmail();
/// final verified = await EmailVerificationService.instance.checkVerified();
/// ```
///
/// Every method is failure-tolerant: an uninitialized Firebase app
/// (`[core/no-app]` during a cold-launch race or a widget test) resolves to a
/// safe default instead of throwing, mirroring the project's service-seam
/// pattern.
///
/// ## Verification-email audit trail (bug fix)
///
/// Email-verification emails are sent by **Firebase Auth itself**
/// (`User.sendEmailVerification()`); there is no Cloud Function in the send
/// path. When that call fails the failure used to be swallowed by a bare
/// `debugPrint`, so there was no record of WHICH account never received the
/// mail. Every send now records an audit trail on `users/{uid}`:
///
///   * [sentField] — `true` only on a confirmed dispatch;
///   * [lastErrorField] — the failure reason (code + message);
///   * [lastAttemptField] — the attempt timestamp.
///
/// These fields are NOT server-owned (they are not frozen in
/// `firestore.rules`), so the owner may write them; the admin portal reads
/// them to identify the accounts that missed their email and to resend.
class EmailVerificationService {
  EmailVerificationService._();
  static final EmailVerificationService instance =
      EmailVerificationService._();

  /// The `users/{uid}` fields the audit trail is written to. Exposed so tests
  /// and the admin portal reference one spelling.
  static const String sentField = 'verificationEmailSent';
  static const String lastErrorField = 'verificationEmailLastError';
  static const String lastAttemptField = 'verificationEmailLastAttemptAt';

  /// Test seam: overrides the Firestore instance (defaults to the live one).
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  /// Test seam: overrides the uid resolver.
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  /// Test seam: overrides the send itself (bypasses FirebaseAuth).
  @visibleForTesting
  Future<void> Function()? sendOverride;

  /// Lazy so constructing the service before `Firebase.initializeApp()`
  /// (cold-launch race / widget test) does not throw `[core/no-app]`.
  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  String? get _uid {
    final override = currentUserIdResolverForTesting;
    if (override != null) return override();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Sends (or re-sends) the verification email to the signed-in user.
  ///
  /// Returns normally when there is no signed-in user (nothing to do) so
  /// callers never have to pre-check auth state.
  ///
  /// The outcome is recorded on `users/{uid}` (see the class doc). The audit
  /// write is best-effort — a Firestore failure never masks the send result.
  Future<void> sendVerificationEmail() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final override = sendOverride;
      if (override != null) {
        await override();
      } else {
        final user = currentUser;
        if (user == null) return;
        await user.sendEmailVerification();
      }
      await _recordOutcome(uid, sent: true);
    } catch (e) {
      // Record the failure so the admin portal can identify the account and
      // resend. Rethrow so the caller (the verification screen) still surfaces
      // the error to the user.
      await _recordOutcome(uid, sent: false, error: _describe(e));
      rethrow;
    }
  }

  /// Writes the verification-email audit trail. Best-effort: never throws.
  Future<void> _recordOutcome(
    String uid, {
    required bool sent,
    String? error,
  }) async {
    try {
      await _db.collection('users').doc(uid).set({
        sentField: sent,
        lastAttemptField: FieldValue.serverTimestamp(),
        if (!sent) lastErrorField: error ?? 'unknown error',
        if (sent) lastErrorField: FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('EmailVerificationService: audit write failed: $e');
    }
  }

  /// A compact, greppable failure description (Firebase error code + message).
  String _describe(Object e) {
    if (e is FirebaseAuthException) {
      final msg = (e.message ?? '').trim();
      return msg.isEmpty ? e.code : '${e.code}: $msg';
    }
    return e.toString();
  }

  /// Reloads the signed-in user and reports whether their email is now
  /// verified. Returns `false` when there is no signed-in user or Firebase is
  /// unavailable.
  ///
  /// The result is MIRRORED onto `users/{uid}.emailVerified` so the admin
  /// portal (which reads Firestore, never the Auth user list) can identify
  /// accounts that still need a resend. Best-effort: a mirror write failure
  /// never affects the returned value.
  Future<bool> checkVerified() async {
    final user = currentUser;
    if (user == null) return false;
    await user.reload();
    final verified = currentUser?.emailVerified ?? false;
    await _mirrorVerified(verified);
    return verified;
  }

  /// Persists the verified flag onto `users/{uid}` (best-effort).
  Future<void> _mirrorVerified(bool verified) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {'emailVerified': verified},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('EmailVerificationService: verified mirror failed: $e');
    }
  }

  /// The live Firebase user, or null when Firebase is unavailable.
  User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// @visibleForTesting — clears the seams between tests.
  @visibleForTesting
  void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    sendOverride = null;
  }
}
