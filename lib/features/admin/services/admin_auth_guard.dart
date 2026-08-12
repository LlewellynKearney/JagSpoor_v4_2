import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin authorization guard.
///
/// Resolves whether the current Firebase user is a platform superuser. A user is
/// considered an admin when EITHER of the following is true:
///
///   1. The user's Firebase ID token carries the custom claim `admin == true`
///      (set out-of-band by a platform operator via the Admin SDK). This is the
///      same claim the Firestore rules check with `request.auth.token.admin`.
///   2. The user's `users/{uid}` document has `role == 'admin'`
///      (the `userRole == 'admin'` case).
///
/// The claim check is authoritative and fast; the Firestore fallback covers
/// accounts that were granted admin via a database flag without a custom claim.
/// Results are cached for the process lifetime and can be refreshed with
/// [refresh].
class AdminAuthGuard {
  AdminAuthGuard._();
  static final AdminAuthGuard instance = AdminAuthGuard._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool? _cached;
  DateTime? _resolvedAt;

  /// The admin email allow-list. Accounts with this exact email are always
  /// treated as admins regardless of claims/database flags, so a platform
  /// operator can bootstrap the first admin without a prior claim grant.
  static const Set<String> _adminEmailAllowList = {
    'admin@jagspoor.co.za',
  };

  /// Returns `true` when the current user is a platform admin.
  Future<bool> isCurrentUserAdmin({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Short-circuit on the bootstrap admin allow-list (by email).
    if (_adminEmailAllowList.contains(user.email?.trim().toLowerCase())) {
      _cached = true;
      _resolvedAt = DateTime.now();
      return true;
    }

    if (_cached != null && !forceRefresh) return _cached!;

    bool admin = false;

    // 1. Custom claim `admin == true` on the ID token.
    try {
      final tokenResult = await user.getIdTokenResult(forceRefresh);
      final claim = tokenResult.claims?['admin'];
      admin = claim == true;
    } catch (_) {
      // Token fetch can fail offline; fall through to the Firestore check.
    }

    // 2. Firestore `users/{uid}.role == 'admin'` fallback.
    if (!admin) {
      try {
        final doc = await _db.collection('users').doc(user.uid).get();
        final role = doc.data()?['role'];
        admin = role == 'admin';
      } catch (_) {
        // Keep whatever the claim check resolved (possibly false).
      }
    }

    _cached = admin;
    _resolvedAt = DateTime.now();
    return admin;
  }

  /// Synchronous accessor for the last resolved value. Returns `false` before
  /// the first async resolution completes.
  bool get lastResolved => _cached ?? false;

  DateTime? get resolvedAt => _resolvedAt;

  /// Re-fetches the admin status (e.g. after a custom-claim grant). Forces a
  /// token refresh so a freshly granted claim is picked up immediately.
  Future<bool> refresh() => isCurrentUserAdmin(forceRefresh: true);

  /// Clears the cached value (call on logout).
  void reset() {
    _cached = null;
    _resolvedAt = null;
  }
}
