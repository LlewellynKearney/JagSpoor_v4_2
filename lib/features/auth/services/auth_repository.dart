import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'user_role_provider.dart';

/// Thrown when the chosen role could not be persisted to `users/{uid}`.
///
/// Role selection is an onboarding gate: if the write silently fails the
/// account stays role-less and the user is bounced through "Select
/// Operational Profile" on every sign-in (the reported v21 defect). Callers
/// must therefore surface this instead of navigating on regardless.
class AuthRolePersistenceException implements Exception {
  const AuthRolePersistenceException(this.message);

  final String message;

  @override
  String toString() => 'AuthRolePersistenceException: $message';
}

/// Firestore access for the authentication / onboarding flow.
///
/// Owns the `users/{uid}` document contract:
///   - [ensureUserDocument] creates the profile document if it is missing
///     (a self-healing net for accounts whose Auth onCreate trigger write
///     never landed) and backfills a missing `email`.
///   - [hasRole] / [storedRole] answer "does this account already have a
///     permanent role?" so post-auth routing can skip role selection.
///   - [saveRole] persists the chosen role and **verifies the write** by
///     reading the document back, retrying once with a minimal payload.
class AuthRepository {
  AuthRepository._();
  static final AuthRepository instance = AuthRepository._();

  /// Test seam: inject a fake Firestore (e.g. `FakeFirebaseFirestore`) so the
  /// document contract can be exercised without a live Firebase app.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Test seam: overrides the role read-back used to verify a [saveRole] write
  /// landed, so the "write silently did not persist" failure path can be
  /// exercised deterministically.
  @visibleForTesting
  static Future<AppRole> Function(String uid)? roleReadbackForTesting;

  /// Test seam: overrides the signed-in identity so the flow is drivable
  /// without a Firebase app (the production getters below resolve the real
  /// `FirebaseAuth` lazily).
  @visibleForTesting
  static ({String uid, String? email})? currentUserForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    roleReadbackForTesting = null;
    currentUserForTesting = null;
  }

  /// The signed-in uid, or null when signed out / Firebase is unavailable.
  ///
  /// `FirebaseAuth.instance` is resolved inside the try so a call before
  /// `Firebase.initializeApp()` (cold-launch race, widget test) resolves null
  /// instead of throwing `[core/no-app]`.
  String? get currentUid {
    final override = currentUserForTesting;
    if (override != null) return override.uid;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// The signed-in account email, or null.
  String? get currentEmail {
    final override = currentUserForTesting;
    if (override != null) return override.email;
    try {
      return FirebaseAuth.instance.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  // Lazy getter so constructing the singleton before `Firebase.initializeApp`
  // (cold-launch race / widget test) does not throw `[core/no-app]`.
  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  static const String usersCollection = 'users';

  /// The role strings this repository persists. Only the two self-selectable
  /// roles are accepted — `admin` is never self-assigned (the Firestore rule
  /// denies it, and [AdminAuthGuard] owns admin detection).
  static const Set<String> selectableRoles = {'hunter', 'outfitter'};

  /// The canonical trial-end / entitlement fields are server-owned; the
  /// create payload deliberately omits `createdAt` (frozen in
  /// `firestore.rules` — stamped by the Auth onCreate trigger via the Admin
  /// SDK) so a client create is not denied.
  static const List<String> _serverOwnedFields = [
    'createdAt',
    'isPremium',
    'premiumExpiry',
    'subscriptionSource',
    'subscriptionStatus',
    'isPro',
  ];

  /// Reads the raw `users/{uid}` document (null when it does not exist).
  /// Never throws.
  Future<Map<String, dynamic>?> readUserDocument(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _db.collection(usersCollection).doc(uid).get();
      return snap.data();
    } catch (e) {
      debugPrint('AuthRepository.readUserDocument($uid) failed: $e');
      return null;
    }
  }

  /// Whether a `users/{uid}` document exists.
  Future<bool> userDocumentExists(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final snap = await _db.collection(usersCollection).doc(uid).get();
      return snap.exists;
    } catch (e) {
      debugPrint('AuthRepository.userDocumentExists($uid) failed: $e');
      return false;
    }
  }

  /// The permanent role stored on `users/{uid}`, or [AppRole.unknown] when the
  /// document is missing / has no role / cannot be read.
  ///
  /// Dual-role detection mirrors [UserRoleProvider.resolveRole] so the two
  /// agree: `isDualRole`, a `roles` array carrying both hunter + outfitter, or
  /// the shorthand `role: 'dual'`.
  Future<AppRole> storedRole(String uid) async {
    final override = roleReadbackForTesting;
    if (override != null) return override(uid);
    final data = await readUserDocument(uid);
    if (data == null) return AppRole.unknown;
    return roleFromUserDocument(data);
  }

  /// Whether the account already carries a permanent role — the signal
  /// post-auth routing uses to skip the role-selection screen.
  Future<bool> hasRole(String uid) async =>
      (await storedRole(uid)) != AppRole.unknown;

  /// Pure role resolution over a `users/{uid}` document map.
  static AppRole roleFromUserDocument(Map<String, dynamic>? data) {
    if (data == null) return AppRole.unknown;
    final stored = data['role'] as String?;
    final roles = data['roles'];
    final isDualRole = data['isDualRole'] == true ||
        (roles is List && roles.contains('outfitter') && roles.contains('hunter')) ||
        stored == 'dual';
    return isDualRole ? AppRole.dual : AppRole.fromString(stored);
  }

  /// Creates the `users/{uid}` document when it is missing and backfills a
  /// missing `email` on an existing one.
  ///
  /// Best-effort by design: a Firestore rejection (offline, or the role-freeze
  /// rule interacting with a first-time create) is logged and swallowed so
  /// sign-in is never blocked by this repair. Returns `true` when the document
  /// is present afterwards.
  Future<bool> ensureUserDocument({
    required String uid,
    String? email,
  }) async {
    if (uid.isEmpty) return false;
    final trimmedEmail = (email ?? '').trim();
    try {
      final snap = await _db.collection(usersCollection).doc(uid).get();
      if (!snap.exists) {
        await _db.collection(usersCollection).doc(uid).set({
          'uid': uid,
          if (trimmedEmail.isNotEmpty) 'email': trimmedEmail,
          'onboardingCompleted': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final storedEmail = (data['email'] as String?)?.trim() ?? '';
      if (storedEmail.isEmpty && trimmedEmail.isNotEmpty) {
        await _db.collection(usersCollection).doc(uid).set({
          'email': trimmedEmail,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return true;
    } catch (e) {
      debugPrint('AuthRepository.ensureUserDocument($uid) failed: $e');
      return false;
    }
  }

  /// Persists the chosen operational role to `users/{uid}` and verifies the
  /// write landed.
  ///
  /// Payload (merge write, so every other profile field survives):
  ///   - `role`              the selected role (`hunter` / `outfitter`)
  ///   - `roleSelectedAt`    server timestamp of the selection
  ///   - `roleSetAt`         legacy alias of the above (kept in sync)
  ///   - `onboardingCompleted: true`
  ///   - `updatedAt`         server timestamp
  ///
  /// The full payload is attempted first; if Firestore rejects it (e.g. a
  /// legacy document tripping one of the change-detection guards) the write is
  /// retried once with only `role` + `updatedAt`, which is the minimum the
  /// role freeze permits. The document is then read back to confirm the role
  /// is actually stored — a silent failure is exactly the bug this fixes.
  ///
  /// Throws [AuthRolePersistenceException] when the role is still absent after
  /// both attempts, so the caller can surface a retry instead of leaving the
  /// account role-less.
  Future<void> saveRole({
    required String uid,
    required String role,
  }) async {
    final normalized = role.trim().toLowerCase();
    if (!selectableRoles.contains(normalized)) {
      throw AuthRolePersistenceException(
        'Unsupported role "$role" — expected one of $selectableRoles.',
      );
    }
    if (uid.isEmpty) {
      throw const AuthRolePersistenceException(
        'You must be signed in to select a role.',
      );
    }

    final ref = _db.collection(usersCollection).doc(uid);

    Future<void> attempt(Map<String, dynamic> payload) async {
      await ref.set(payload, SetOptions(merge: true));
    }

    Object? firstError;
    try {
      await attempt({
        'role': normalized,
        'roleSelectedAt': FieldValue.serverTimestamp(),
        'roleSetAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      firstError = e;
      debugPrint('AuthRepository.saveRole full payload failed ($uid): $e');
      try {
        await attempt({
          'role': normalized,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (retryError) {
        debugPrint('AuthRepository.saveRole minimal payload failed ($uid): '
            '$retryError');
        throw AuthRolePersistenceException(
          'Could not save your role: $retryError',
        );
      }
    }

    // Verify — a write that "succeeds" but does not persist is the failure
    // mode that left accounts role-less.
    final stored = await storedRole(uid);
    if (stored == AppRole.unknown) {
      throw AuthRolePersistenceException(
        'Your role could not be confirmed after saving'
        '${firstError == null ? '' : ' ($firstError)'}. '
        'Please check your connection and try again.',
      );
    }
  }

  /// Fields the client must never write on `users/{uid}` (server-owned /
  /// frozen in `firestore.rules`). Exposed so tests can assert the create
  /// payload stays clear of them.
  @visibleForTesting
  static List<String> get serverOwnedFields => List.unmodifiable(_serverOwnedFields);
}
