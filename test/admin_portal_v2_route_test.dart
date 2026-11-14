// ============================================================================
// Admin Portal V2 route — `/admin_portal_v2` must load AdminPortalV2Screen.
//
// BUG (live screenshot): opening the PATH-based URL
// `https://jag-spoor.co.za/admin_portal_v2` (no `#`) landed on the OLD Admin
// Portal (`#/admin_dashboard`: Instant Mode Switcher + Entity Overview).
//
// ROOT CAUSE: the app uses hash routing, so Flutter's web engine derives its
// default route from the URL hash (`HashUrlStrategy.getPath()` reads only
// `location.hash` and returns `/` when it is empty). A path deep link has an
// empty hash, so `WidgetsApp` fell back to its hard-coded `initialRoute`
// (`/splash`) and the splash routed a signed-in admin to `/admin_dashboard`.
//
// These tests cover the pure fix (`AppRouter.resolveInitialRoute`) and the
// `main.dart` route table that consumes it.
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/router/app_router.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Pure resolution — the fix.
  // ---------------------------------------------------------------------------
  group('AppRouter.resolveInitialRoute', () {
    String resolve({String hash = '', String path = ''}) =>
        AppRouter.resolveInitialRoute(
          hashRoute: hash,
          browserPath: path,
          isKnownRoute: AppRoutes.all.contains,
        );

    test('path deep link /admin_portal_v2 resolves to the V2 route', () {
      // The reported bug: a path URL (empty hash) must NOT fall back to splash.
      expect(resolve(path: '/admin_portal_v2'), AppRoutes.adminPortalV2);
    });

    test('hash deep link #/admin_portal_v2 still resolves to the V2 route', () {
      expect(resolve(hash: '/admin_portal_v2'), AppRoutes.adminPortalV2);
    });

    test('hash route wins over the browser path when both are present', () {
      expect(
        resolve(hash: '/admin_portal_v2', path: '/hunter_dashboard'),
        AppRoutes.adminPortalV2,
      );
    });

    test('path deep link /admin resolves to the OLD portal (alias)', () {
      expect(resolve(path: '/admin'), AppRoutes.adminDashboard);
    });

    test('path deep link /admin_dashboard resolves to the OLD portal', () {
      expect(resolve(path: '/admin_dashboard'), AppRoutes.adminDashboard);
    });

    test('path alias /admin-portal-v2 resolves to the V2 route', () {
      expect(resolve(path: '/admin-portal-v2'), AppRoutes.adminPortalV2);
    });

    test('root path (no deep link) falls back to the splash', () {
      expect(resolve(), AppRoutes.splash);
      expect(resolve(hash: '/', path: '/'), AppRoutes.splash);
    });

    test('an unknown path falls back to the splash', () {
      expect(resolve(path: '/not_a_real_route'), AppRoutes.splash);
    });

    test('an unknown hash falls back to the splash', () {
      expect(resolve(hash: '/not_a_real_route'), AppRoutes.splash);
    });

    test('a trailing slash + query string are normalised', () {
      expect(resolve(path: '/admin_portal_v2/'), AppRoutes.adminPortalV2);
      expect(
        resolve(path: '/admin_portal_v2?tab=users'),
        AppRoutes.adminPortalV2,
      );
    });
  });

  group('AppRouter.normalizePath', () {
    test('strips a leading #/ fragment', () {
      expect(AppRouter.normalizePath('#/admin_portal_v2'),
          '/admin_portal_v2');
    });

    test('collapses duplicate slashes and a trailing slash', () {
      expect(AppRouter.normalizePath('//admin_portal_v2//'),
          '/admin_portal_v2');
    });

    test('drops a query string', () {
      expect(AppRouter.normalizePath('/admin_portal_v2?x=1'),
          '/admin_portal_v2');
    });

    test('adds a leading slash to a bare path', () {
      expect(AppRouter.normalizePath('admin_portal_v2'), '/admin_portal_v2');
    });

    test('empty / blank / bare-hash inputs normalise to empty', () {
      expect(AppRouter.normalizePath(''), '');
      expect(AppRouter.normalizePath('   '), '');
      expect(AppRouter.normalizePath('#'), '');
      expect(AppRouter.normalizePath(null), '');
    });
  });

  group('AppRouter.resolvePathAlias', () {
    test('/admin keeps the OLD portal reachable', () {
      expect(AppRouter.resolvePathAlias('/admin'), AppRoutes.adminDashboard);
    });

    test('matching is case-insensitive', () {
      expect(AppRouter.resolvePathAlias('/ADMIN-PORTAL-V2'),
          AppRoutes.adminPortalV2);
    });

    test('a non-alias path returns null', () {
      expect(AppRouter.resolvePathAlias('/hunter_dashboard'), isNull);
    });
  });

  group('AppRoutes constants', () {
    test('both admin portals are registered, with the old portal retained', () {
      expect(AppRoutes.adminPortalV2, '/admin_portal_v2');
      expect(AppRoutes.adminDashboard, '/admin_dashboard');
      expect(AppRoutes.all, contains(AppRoutes.adminPortalV2));
      expect(AppRoutes.all, contains(AppRoutes.adminDashboard));
      expect(AppRoutes.all, contains(AppRoutes.adminLegacy));
    });
  });

  // ---------------------------------------------------------------------------
  // main.dart route table — the V2 route maps to the V2 screen, and the old
  // portal is preserved (not redirected away).
  // ---------------------------------------------------------------------------
  group('main.dart route table', () {
    final main =
        File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    /// The `'/route': (context) => …` keys in the `routes:` map.
    Set<String> registeredRoutes() {
      final matches = RegExp(r"'(\/[a-z_0-9]*)':\s*\(context\)")
          .allMatches(main);
      return matches.map((m) => m.group(1)!).toSet();
    }

    /// The body of a route registration, from its key to the next route key.
    String routeBlock(String route) {
      final start = main.indexOf("'$route':");
      expect(start, greaterThan(-1), reason: '$route must be registered');
      final rest = main.substring(start + route.length + 4);
      final next = RegExp(r"'\/[a-z_0-9]*':\s*\(context\)").firstMatch(rest);
      return next == null ? rest : rest.substring(0, next.start);
    }

    test('the registered routes match AppRoutes.all exactly', () {
      expect(registeredRoutes(), AppRoutes.all);
    });

    test('/admin_portal_v2 loads AdminPortalV2Screen directly (no redirect)',
        () {
      final block = routeBlock('/admin_portal_v2');
      expect(block, contains('AdminPortalV2Screen'));
      // The bug was a redirect to the OLD dashboard — it must never come back.
      expect(block, isNot(contains('pushReplacementNamed')));
      expect(block, isNot(contains('/admin_dashboard')));
    });

    test('/admin_dashboard still loads the OLD AdminDashboardScreen', () {
      final block = routeBlock('/admin_dashboard');
      expect(block, contains('AdminDashboardScreen'));
    });

    test('/admin (alias) also loads the OLD AdminDashboardScreen', () {
      final block = routeBlock('/admin');
      expect(block, contains('AdminDashboardScreen'));
    });

    test('the boot route is resolved from the hash AND the browser path', () {
      expect(main, contains('_resolveBootRoute'));
      expect(main, contains('currentBrowserPath()'));
      expect(main, contains('AppRouter.resolveInitialRoute'));
      expect(main, contains('initialRoute: initialRoute'));
    });
  });
}
