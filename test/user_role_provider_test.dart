// ============================================================================
// Role-Based Access Control (RBAC) — UserRoleProvider caching contract tests
//
// Exercises the provider's cache (setRole / resolveRole cache-hit / reset /
// getters) WITHOUT touching Firebase. This keeps the suite green in any
// environment (the Firestore `users/{uid}.role` fetch itself is a one-line
// read + AppRole.fromString, whose mapping is covered by role_guard_test.dart
// and exercised end-to-end where the Firebase emulator / credentials exist).
//
// The Firestore-backed resolution path (admin / outfitter / hunter / unknown
// from `users/{uid}.role`) is implemented in UserRoleProvider.resolveRole and
// covered by AppRole.fromString's round-trip tests below the guard tests.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:jagspoor/features/auth/services/role_guard.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

void main() {
  setUp(() {
    UserRoleProvider.instance.reset();
  });

  tearDown(() {
    UserRoleProvider.instance.reset();
  });

  group('UserRoleProvider — default state', () {
    test('starts unresolved as unknown', () {
      expect(UserRoleProvider.instance.role, AppRole.unknown);
      expect(UserRoleProvider.instance.isResolved, isFalse);
      expect(UserRoleProvider.instance.isAdmin, isFalse);
      expect(UserRoleProvider.instance.isOutfitter, isFalse);
      expect(UserRoleProvider.instance.isHunter, isFalse);
      expect(UserRoleProvider.instance.isDual, isFalse);
      expect(UserRoleProvider.instance.hasOutfitterAccess, isFalse);
      expect(UserRoleProvider.instance.hasHunterAccess, isFalse);
    });
  });

  group('UserRoleProvider.setRole', () {
    test('caches admin and flips the getters', () {
      UserRoleProvider.instance.setRole(AppRole.admin);
      expect(UserRoleProvider.instance.role, AppRole.admin);
      expect(UserRoleProvider.instance.isAdmin, isTrue);
      expect(UserRoleProvider.instance.isOutfitter, isFalse);
      expect(UserRoleProvider.instance.isResolved, isTrue);
    });

    test('caches outfitter', () {
      UserRoleProvider.instance.setRole(AppRole.outfitter);
      expect(UserRoleProvider.instance.isOutfitter, isTrue);
      expect(UserRoleProvider.instance.isAdmin, isFalse);
    });

    test('caches hunter', () {
      UserRoleProvider.instance.setRole(AppRole.hunter);
      expect(UserRoleProvider.instance.isHunter, isTrue);
    });

    test('caches dual and flips BOTH access getters', () {
      UserRoleProvider.instance.setRole(AppRole.dual);
      expect(UserRoleProvider.instance.role, AppRole.dual);
      expect(UserRoleProvider.instance.isDual, isTrue);
      expect(UserRoleProvider.instance.isAdmin, isFalse);
      expect(UserRoleProvider.instance.hasOutfitterAccess, isTrue);
      expect(UserRoleProvider.instance.hasHunterAccess, isTrue);
      // Dual is a non-admin — the access getters are the admission knobs.
      expect(UserRoleProvider.instance.isOutfitter, isFalse);
      expect(UserRoleProvider.instance.isHunter, isFalse);
    });
  });

  group('UserRoleProvider.resolveRole — cache contract', () {
    test('returns the cached role without a re-fetch (cache hit)', () async {
      UserRoleProvider.instance.setRole(AppRole.outfitter);
      // resolveRole must short-circuit on _resolved && !forceRefresh, so it
      // never touches Firebase (which is not initialized in unit tests).
      final role = await UserRoleProvider.instance.resolveRole();
      expect(role, AppRole.outfitter);
    });

    test('cache hit returns admin when admin was set', () async {
      UserRoleProvider.instance.setRole(AppRole.admin);
      expect(await UserRoleProvider.instance.resolveRole(), AppRole.admin);
      expect(RoleGuard.canSwitchModes(UserRoleProvider.instance.role), isTrue);
    });
  });

  group('UserRoleProvider.resolveRole — Firestore dual-role detection', () {
    test('resolves AppRole.dual from the seeded isDualRole flag', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('demo-uid').set({
        'role': 'dual',
        'isDualRole': true,
        'roles': ['hunter', 'outfitter'],
      });
      UserRoleProvider.instance.injectForTesting(
        db: db,
        testUid: 'demo-uid',
        testEmail: 'demo@jagspoor.co.za',
      );
      final role = await UserRoleProvider.instance.resolveRole(forceRefresh: true);
      expect(role, AppRole.dual);
      expect(UserRoleProvider.instance.hasOutfitterAccess, isTrue);
      expect(UserRoleProvider.instance.hasHunterAccess, isTrue);
      expect(RoleGuard.canSwitchModes(role), isTrue);
    });

    test('resolves AppRole.dual from a roles-list without the flag', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('demo-uid').set({
        'role': 'hunter',
        'roles': ['outfitter', 'hunter'],
      });
      UserRoleProvider.instance.injectForTesting(
        db: db,
        testUid: 'demo-uid',
        testEmail: 'demo@jagspoor.co.za',
      );
      expect(
        await UserRoleProvider.instance.resolveRole(forceRefresh: true),
        AppRole.dual,
      );
    });

    test('resolves AppRole.dual from the plain role: "dual" shorthand', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('demo-uid').set({
        'role': 'dual',
      });
      UserRoleProvider.instance.injectForTesting(
        db: db,
        testUid: 'demo-uid',
        testEmail: 'demo@jagspoor.co.za',
      );
      expect(
        await UserRoleProvider.instance.resolveRole(forceRefresh: true),
        AppRole.dual,
      );
    });

    test('does NOT emit dual for a single-role users doc', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('demo-uid').set({
        'role': 'outfitter',
      });
      UserRoleProvider.instance.injectForTesting(
        db: db,
        testUid: 'demo-uid',
        testEmail: 'demo@jagspoor.co.za',
      );
      final role = await UserRoleProvider.instance.resolveRole(forceRefresh: true);
      expect(role, AppRole.outfitter);
      expect(UserRoleProvider.instance.hasOutfitterAccess, isTrue);
      expect(UserRoleProvider.instance.hasHunterAccess, isFalse);
    });
  });

  group('UserRoleProvider.reset', () {
    test('clears a cached role back to unknown / unresolved', () {
      UserRoleProvider.instance.setRole(AppRole.hunter);
      expect(UserRoleProvider.instance.isResolved, isTrue);

      UserRoleProvider.instance.reset();
      expect(UserRoleProvider.instance.role, AppRole.unknown);
      expect(UserRoleProvider.instance.isResolved, isFalse);
      expect(UserRoleProvider.instance.isHunter, isFalse);
    });
  });
}

