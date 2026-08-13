import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:meta/meta.dart';

import '../../admin/services/admin_auth_guard.dart';

/// The resolved operational role of the signed-in user.
enum AppRole {
  /// Platform superuser — full access to the Admin Portal and instant mode
  /// switching across all profiles.
  admin,

  /// Game-farm operator — defaults to Outfitter Mode; cannot open the Admin
  /// Portal or Hunter Mode.
  outfitter,

  /// Field user — defaults to Hunter Mode; cannot open the Admin Portal or
  /// Outfitter Management functions.
  hunter,

  /// Role not yet resolved (pre-login, in-flight resolution, or fetch error).
  unknown;

  /// Parses the raw role string stored on the Firestore `users/{uid}` document.
  /// Unknown / null values collapse to [AppRole.unknown] so callers can route
  /// the user to role selection rather than guessing.
  static AppRole fromString(String? value) {
    switch (value) {
      case 'admin':
        return AppRole.admin;
      case 'outfitter':
        return AppRole.outfitter;
      case 'hunter':
        return AppRole.hunter;
      default:
        return AppRole.unknown;
    }
  }
}

/// Central, cached source of truth for the current user's resolved role.
///
/// On login the role is fetched from Firestore (`users/{uid}.role`) and — for
/// the admin path — from the [AdminAuthGuard] (custom claim, email allow-list,
/// and the `outfitters/{uid}.role` flag). The result is cached for the process
/// lifetime so every screen / route guard reads a single consistent value
/// instead of each re-resolving independently.
///
/// Call [resolveRole] after sign-in / on splash, [setRole] after a role
/// selection write, and [reset] on sign-out.
class UserRoleProvider {
  UserRoleProvider._();
  static final UserRoleProvider instance = UserRoleProvider._();

  // Injectable for unit tests; default to the production singletons. These
  // are lazily resolved (via getters) so simply touching the provider in a
  // unit test — before Firebase is initialized — does not throw.
  FirebaseFirestore? _dbOverride;
  FirebaseAuth? _authOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  // Test-only overrides for the current user's uid / email (so the Firestore
  // role-fetch path can be exercised with FakeFirebaseFirestore + a hand-set
  // uid, without a real FirebaseAuth instance). Null in production.
  String? _testUid;
  String? _testEmail;

  AppRole _role = AppRole.unknown;
  bool _resolved = false;

  AppRole get role => _role;
  bool get isResolved => _resolved;
  bool get isAdmin => _role == AppRole.admin;
  bool get isOutfitter => _role == AppRole.outfitter;
  bool get isHunter => _role == AppRole.hunter;

  /// The admin email allow-list mirrors [AdminAuthGuard] so a bootstrap admin
  /// is detected here too without a custom-claim round-trip.
  static const Set<String> _adminEmailAllowList = {
    'admin@jag-spoor.co.za',
  };

  /// Resolves and caches the current user's role.
  ///
  /// Resolution order:
  ///   1. Not signed in → [AppRole.unknown].
  ///   2. Admin email allow-list → [AppRole.admin].
  ///   3. [AdminAuthGuard] admin claim / Firestore flag → [AppRole.admin].
  ///   4. `users/{uid}.role` → the stored role.
  ///   5. No doc / fetch error → [AppRole.unknown].
  ///
  /// Pass [forceRefresh] to bypass the cache (e.g. after a role grant).
  Future<AppRole> resolveRole({bool forceRefresh = false}) async {
    if (_resolved && !forceRefresh) return _role;

    final user = _testUid != null ? null : _auth.currentUser;
    // uid/email come from the real auth user, or the test overrides.
    final uid = _testUid ?? user?.uid;
    final email = _testEmail ?? user?.email;

    // 1. Not signed in → unknown (guards will route to login).
    if (uid == null) {
      _role = AppRole.unknown;
      _resolved = true;
      return _role;
    }

    // 2. Bootstrap admin email allow-list.
    if (_adminEmailAllowList.contains(email?.trim().toLowerCase())) {
      _role = AppRole.admin;
      _resolved = true;
      return _role;
    }

    // 3. Admin via custom claim / Firestore admin flag (delegated to the
    //    existing guard so the claim logic stays in one place). Skipped when
    //    running under a test-uid override (no real FirebaseAuth user).
    if (_testUid == null) {
      try {
        if (await AdminAuthGuard.instance
            .isCurrentUserAdmin(forceRefresh: forceRefresh)) {
          _role = AppRole.admin;
          _resolved = true;
          return _role;
        }
      } catch (_) {
        // Claim fetch can fail offline; fall through to the users doc.
      }
    }

    // 4. Firestore users/{uid}.role.
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final stored = doc.data()?['role'] as String?;
      _role = AppRole.fromString(stored);
    } catch (_) {
      _role = AppRole.unknown;
    }

    _resolved = true;
    return _role;
  }

  /// Sets the role directly (used after a role-selection write so the guard
  /// sees the freshly chosen role without a re-fetch).
  void setRole(AppRole role) {
    _role = role;
    _resolved = true;
  }

  /// Clears the cached role (call on sign-out).
  void reset() {
    _role = AppRole.unknown;
    _resolved = false;
    _testUid = null;
    _testEmail = null;
  }

  /// For unit tests: inject fake Firestore / auth instances and clear cache.
  /// Pass [testUid] / [testEmail] to simulate a signed-in user without a real
  /// FirebaseAuth instance (the Firestore role-fetch path is then exercised
  /// against [db]).
  @visibleForTesting
  void injectForTesting({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    String? testUid,
    String? testEmail,
  }) {
    if (db != null) _dbOverride = db;
    if (auth != null) _authOverride = auth;
    _testUid = testUid;
    _testEmail = testEmail;
    _role = AppRole.unknown;
    _resolved = false;
  }
}
