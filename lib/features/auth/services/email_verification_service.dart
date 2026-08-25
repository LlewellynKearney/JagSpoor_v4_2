import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'email_verification_guard.dart';

/// Immutable snapshot of the signed-in user's email-verification state.
class EmailVerificationStatus {
  const EmailVerificationStatus({
    required this.isSignedIn,
    required this.email,
    required this.emailVerified,
  });

  /// Whether a Firebase Auth session exists.
  final bool isSignedIn;

  /// The account's email address (empty when the account has none).
  final String email;

  /// Firebase Auth's `emailVerified` flag (read after a `reload()` for a
  /// fresh value).
  final bool emailVerified;

  /// The account carries an email address at all (phone-only accounts do
  /// not — they are exempt from the email-verification gate).
  bool get hasEmailAddress => email.trim().isNotEmpty;

  /// Whether [EmailVerificationGuard] blocks this account from core
  /// features until the email is verified.
  bool get requiresVerification => EmailVerificationGuard.requiresVerification(
        isSignedIn: isSignedIn,
        hasEmailAddress: hasEmailAddress,
        emailVerified: emailVerified,
      );
}

/// Thin wrapper around Firebase Auth's built-in email-verification flow.
///
/// Firebase Auth dispatches the verification email itself (the project's
/// Auth email templates / SMTP configuration — the JagSpoor mail domain is
/// hosted on Afrihost — govern the sender). This service exposes the three
/// operations the verification screen + the auth/route guards need, all
/// lazily resolved so construction before `Firebase.initializeApp()` (cold
/// launch / widget tests) never throws `[core/no-app]`:
///
///  - [currentStatus] — snapshot the signed-in user's verification state.
///  - [sendVerificationEmail] — (re)send the verification link.
///  - [refreshStatus] — `reload()` the user and re-read `emailVerified`.
class EmailVerificationService {
  EmailVerificationService._();

  /// Process-wide singleton.
  static final EmailVerificationService instance = EmailVerificationService._();

  // --- Test seams -----------------------------------------------------------
  // Static overrides so the guards (splash / auth screen / RoleGuardedRoute)
  // and the verification screen can be exercised without a live Firebase app.
  @visibleForTesting
  static Future<EmailVerificationStatus> Function()? statusResolverForTesting;
  @visibleForTesting
  static Future<void> Function()? verificationSenderForTesting;
  @visibleForTesting
  static Future<bool> Function()? statusRefresherForTesting;
  @visibleForTesting
  static Future<void> Function()? signOutForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    statusResolverForTesting = null;
    verificationSenderForTesting = null;
    statusRefresherForTesting = null;
    signOutForTesting = null;
  }

  // --- Production operations ------------------------------------------------

  /// Snapshot of the current user's verification state. Never throws: a
  /// signed-out / uninitialized-Firebase state resolves to a signed-out
  /// status (no verification requirement).
  Future<EmailVerificationStatus> currentStatus() async {
    final resolver = statusResolverForTesting;
    if (resolver != null) return resolver();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const EmailVerificationStatus(
          isSignedIn: false,
          email: '',
          emailVerified: false,
        );
      }
      return EmailVerificationStatus(
        isSignedIn: true,
        email: user.email ?? '',
        emailVerified: user.emailVerified,
      );
    } catch (_) {
      // [core/no-app] during a cold-launch race — treat as signed-out.
      return const EmailVerificationStatus(
        isSignedIn: false,
        email: '',
        emailVerified: false,
      );
    }
  }

  /// (Re)sends Firebase Auth's built-in verification email to the current
  /// user. Throws [StateError] when no signed-in user carries an email
  /// address; propagates [FirebaseAuthException] (e.g. `too-many-requests`)
  /// so the UI can surface the specific reason.
  Future<void> sendVerificationEmail() async {
    final override = verificationSenderForTesting;
    if (override != null) return override();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email ?? '').trim().isEmpty) {
      throw StateError(
        'Cannot send a verification email: no signed-in user with an email address.',
      );
    }
    await user.sendEmailVerification();
  }

  /// Reloads the current user from Firebase Auth and returns the fresh
  /// `emailVerified` flag (`false` when signed out).
  Future<bool> refreshStatus() async {
    final override = statusRefresherForTesting;
    if (override != null) return override();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reload();
      return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Signs the current user out (used by the verification screen's
  /// "use a different account" action). Never throws.
  Future<void> signOut() async {
    final override = signOutForTesting;
    if (override != null) return override();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Best-effort: an uninitialized Firebase app means there is no session.
    }
  }
}
