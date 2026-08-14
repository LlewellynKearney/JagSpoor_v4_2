// ============================================================================
// Role-Based Access Control (RBAC) — RoleGuard unit tests
//
// Verifies the pure role-guard policy for admin, outfitter, hunter, and
// unknown profiles: route access, default-home routing, mode-switcher
// gating, and access-denied messaging. No Firebase / Flutter bindings
// required — RoleGuard is dependency-free by design.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/auth/services/role_guard.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

void main() {
  group('AppRole.fromString', () {
    test('parses known roles', () {
      expect(AppRole.fromString('admin'), AppRole.admin);
      expect(AppRole.fromString('outfitter'), AppRole.outfitter);
      expect(AppRole.fromString('hunter'), AppRole.hunter);
    });

    test('collapses null / unknown / empty to unknown', () {
      expect(AppRole.fromString(null), AppRole.unknown);
      expect(AppRole.fromString(''), AppRole.unknown);
      expect(AppRole.fromString('superuser'), AppRole.unknown);
      expect(AppRole.fromString('ADMIN'), AppRole.unknown); // case-sensitive
    });
  });

  group('RoleGuard.canAccess — admin full cross-mode access', () {
    // Admins must be able to reach every dashboard / screen without ever
    // triggering an Access Denied banner — including admin-only routes.
    const allRoutes = <String>[
      '/admin_dashboard',
      '/hunter_dashboard',
      '/outfitter_dashboard',
      '/scan_license',
      '/add_trophy',
      '/role_selection',
      '/some_future_route',
    ];
    for (final route in allRoutes) {
      test('admin may access $route', () {
        expect(RoleGuard.canAccess(AppRole.admin, route), isTrue);
      });
    }
  });

  group('RoleGuard.canAccess — admin-only routes', () {
    for (final route in RoleGuard.adminOnlyRoutes) {
      test('admin may access $route', () {
        expect(RoleGuard.canAccess(AppRole.admin, route), isTrue);
      });

      test('outfitter is denied $route', () {
        expect(RoleGuard.canAccess(AppRole.outfitter, route), isFalse);
      });

      test('hunter is denied $route', () {
        expect(RoleGuard.canAccess(AppRole.hunter, route), isFalse);
      });

      test('unknown is denied $route', () {
        expect(RoleGuard.canAccess(AppRole.unknown, route), isFalse);
      });
    }
  });

  group('RoleGuard.canAccess — hunter dashboard', () {
    test('hunter may access', () {
      expect(RoleGuard.canAccess(AppRole.hunter, '/hunter_dashboard'), isTrue);
    });

    test('admin may preview', () {
      expect(RoleGuard.canAccess(AppRole.admin, '/hunter_dashboard'), isTrue);
    });

    test('outfitter is denied (cannot access hunter functions)', () {
      expect(
          RoleGuard.canAccess(AppRole.outfitter, '/hunter_dashboard'), isFalse);
    });

    test('unknown is denied', () {
      expect(
          RoleGuard.canAccess(AppRole.unknown, '/hunter_dashboard'), isFalse);
    });
  });

  group('RoleGuard.canAccess — outfitter dashboard', () {
    test('outfitter may access', () {
      expect(
          RoleGuard.canAccess(AppRole.outfitter, '/outfitter_dashboard'), isTrue);
    });

    test('admin may preview', () {
      expect(
          RoleGuard.canAccess(AppRole.admin, '/outfitter_dashboard'), isTrue);
    });

    test('hunter is denied (cannot access outfitter management)', () {
      expect(RoleGuard.canAccess(AppRole.hunter, '/outfitter_dashboard'),
          isFalse);
    });

    test('unknown is denied', () {
      expect(
          RoleGuard.canAccess(AppRole.unknown, '/outfitter_dashboard'), isFalse);
    });
  });

  group('RoleGuard.canAccess — non-restricted routes', () {
    test('every role may open forms / detail screens', () {
      for (final role in AppRole.values) {
        expect(RoleGuard.canAccess(role, '/scan_license'), isTrue);
        expect(RoleGuard.canAccess(role, '/add_trophy'), isTrue);
        expect(RoleGuard.canAccess(role, '/role_selection'), isTrue);
      }
    });
  });

  group('RoleGuard.defaultHomeFor', () {
    test('admin → admin dashboard', () {
      expect(RoleGuard.defaultHomeFor(AppRole.admin), '/admin_dashboard');
    });

    test('outfitter → outfitter dashboard', () {
      expect(RoleGuard.defaultHomeFor(AppRole.outfitter), '/outfitter_dashboard');
    });

    test('hunter → hunter dashboard', () {
      expect(RoleGuard.defaultHomeFor(AppRole.hunter), '/hunter_dashboard');
    });

    test('unknown → role selection (never dropped on a dashboard)', () {
      expect(RoleGuard.defaultHomeFor(AppRole.unknown), '/role_selection');
    });
  });

  group('RoleGuard.canSwitchModes', () {
    test('only admins may use the instant mode switcher', () {
      expect(RoleGuard.canSwitchModes(AppRole.admin), isTrue);
      expect(RoleGuard.canSwitchModes(AppRole.outfitter), isFalse);
      expect(RoleGuard.canSwitchModes(AppRole.hunter), isFalse);
      expect(RoleGuard.canSwitchModes(AppRole.unknown), isFalse);
    });
  });

  group('RoleGuard.accessDeniedMessage', () {
    test('admin-only route mentions admin privileges', () {
      final msg = RoleGuard.accessDeniedMessage(
          AppRole.hunter, '/admin_dashboard');
      expect(msg.toLowerCase(), contains('admin'));
    });

    test('outfitter dashboard denied mentions outfitter account', () {
      final msg = RoleGuard.accessDeniedMessage(
          AppRole.hunter, '/outfitter_dashboard');
      expect(msg.toLowerCase(), contains('outfitter'));
    });

    test('hunter dashboard denied mentions hunter', () {
      final msg = RoleGuard.accessDeniedMessage(
          AppRole.outfitter, '/hunter_dashboard');
      expect(msg.toLowerCase(), contains('hunter'));
    });

    test('every message starts with "Access Denied"', () {
      for (final role in AppRole.values) {
        for (final route in [
          '/admin_dashboard',
          '/hunter_dashboard',
          '/outfitter_dashboard',
          '/some_other_route',
        ]) {
          expect(RoleGuard.accessDeniedMessage(role, route),
              startsWith('Access Denied'));
        }
      }
    });
  });

  // ==========================================================================
  // Post-auth direct role routing contract (Item #10).
  //
  // Documents the role -> destination route mapping implemented by
  // SplashScreen._navigateToNextScreen + AuthScreen._routeAfterAuth: a user
  // with a permanent single role is routed straight to their dashboard,
  // bypassing the "Select Operational Profile" screen. Role selection is the
  // fallback for `unknown` (no role / fetch error / dual-role / unassigned).
  // The guard policy must ADMIT the routed role to that route, so this also
  // asserts canAccess holds for every (role, destination) pair the router
  // emits.
  // ==========================================================================
  group('Post-auth direct role routing contract', () {
    const roleRoutes = <AppRole, String>{
      AppRole.admin: '/admin_dashboard',
      AppRole.hunter: '/hunter_dashboard',
      AppRole.outfitter: '/outfitter_dashboard',
    };

    test('each permanent single role routes to exactly one dashboard', () {
      // The mapping is exhaustive over the three permanent roles.
      expect(roleRoutes.length, 3);
      expect(roleRoutes[AppRole.admin], '/admin_dashboard');
      expect(roleRoutes[AppRole.hunter], '/hunter_dashboard');
      expect(roleRoutes[AppRole.outfitter], '/outfitter_dashboard');
    });

    test('routed role is admitted by the route guard (no access-denied loop)',
        () {
      for (final entry in roleRoutes.entries) {
        expect(RoleGuard.canAccess(entry.key, entry.value), isTrue,
            reason:
                '${entry.key} routed to ${entry.value} must be admitted by the guard');
      }
    });

    test('unknown role is NOT routed to any dashboard (goes to selection)', () {
      expect(roleRoutes.keys.contains(AppRole.unknown), isFalse);
      // And the guard denies unknown access to each dashboard, so a stale
      // unknown never slips onto a dashboard via the guard either.
      for (final route in roleRoutes.values) {
        expect(RoleGuard.canAccess(AppRole.unknown, route), isFalse);
      }
    });

    test('AppRole.fromString drives the bypass: outfitter/hunter short-circuit',
        () {
      // The router resolves the role from users/{uid}.role via fromString; an
      // outfitter/hunter string must produce the matching AppRole so the
      // bypass branch fires.
      expect(AppRole.fromString('outfitter'), AppRole.outfitter);
      expect(AppRole.fromString('hunter'), AppRole.hunter);
      // Anything else (including 'unassigned' / 'dual') must fall through to
      // role selection, not a dashboard.
      expect(AppRole.fromString('unassigned'), AppRole.unknown);
      expect(AppRole.fromString('dual'), AppRole.unknown);
    });
  });
}
