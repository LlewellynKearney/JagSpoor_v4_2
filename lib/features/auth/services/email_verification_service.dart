import 'package:firebase_auth/firebase_auth.dart';

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
class EmailVerificationService {
  EmailVerificationService._();
  static final EmailVerificationService instance =
      EmailVerificationService._();

  /// Sends (or re-sends) the verification email to the signed-in user.
  ///
  /// Returns normally when there is no signed-in user (nothing to do) so
  /// callers never have to pre-check auth state.
  Future<void> sendVerificationEmail() async {
    final user = currentUser;
    if (user == null) return;
    await user.sendEmailVerification();
  }

  /// Reloads the signed-in user and reports whether their email is now
  /// verified. Returns `false` when there is no signed-in user or Firebase is
  /// unavailable.
  Future<bool> checkVerified() async {
    final user = currentUser;
    if (user == null) return false;
    await user.reload();
    return currentUser?.emailVerified ?? false;
  }

  /// The live Firebase user, or null when Firebase is unavailable.
  User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }
}
