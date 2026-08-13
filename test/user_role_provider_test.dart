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

