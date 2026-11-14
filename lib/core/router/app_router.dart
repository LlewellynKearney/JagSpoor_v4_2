/// Named-route constants and initial-route resolution for the app.
///
/// The app uses **hash-based** routing, so Flutter's web engine derives its
/// default route from the URL hash (`#/admin_portal_v2`). A *path*-based deep
/// link — `https://jag-spoor.co.za/admin_portal_v2`, no `#` — leaves the hash
/// empty, and `WidgetsApp` then falls back to its hard-coded `initialRoute`
/// (`/splash`). The splash routes a signed-in admin to `/admin_dashboard`, so
/// a path deep link used to land on the OLD Admin Portal instead of the
/// requested screen.
///
/// [AppRouter.resolveInitialRoute] is the pure fix: it prefers a hash route,
/// then a path route (honouring a few friendly aliases), and only then the
/// splash fallback. It is dependency-free so it is fully unit-testable.
library;

/// Canonical named routes. The single source of truth for the route strings
/// used by `main.dart`, so a typo cannot silently register a dead route.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String auth = '/';
  static const String roleSelection = '/role_selection';
  static const String hunterDashboard = '/hunter_dashboard';
  static const String outfitterDashboard = '/outfitter_dashboard';

  /// The ORIGINAL Admin Portal (entity overview + instant mode switcher).
  static const String adminDashboard = '/admin_dashboard';

  /// Friendly alias for the ORIGINAL Admin Portal, so `/admin` stays reachable
  /// after the V2 split (the old portal is NOT removed).
  static const String adminLegacy = '/admin';

  /// Admin Portal V2 — the trial/subscription KPI surface.
  static const String adminPortalV2 = '/admin_portal_v2';

  static const String scanLicense = '/scan_license';
  static const String addFirearmForm = '/add_firearm_form';
  static const String trophyDetail = '/trophy_detail';
  static const String addTrophy = '/add_trophy';
  static const String editTrophy = '/edit_trophy';

  /// Every route registered in `main.dart`. `AppRouter` uses this to reject a
  /// deep link that names no real route, and a contract test asserts the set
  /// stays in step with the `routes:` table so the two cannot drift.
  static const Set<String> all = <String>{
    splash,
    auth,
    roleSelection,
    hunterDashboard,
    outfitterDashboard,
    adminDashboard,
    adminLegacy,
    adminPortalV2,
    scanLicense,
    addFirearmForm,
    trophyDetail,
    addTrophy,
    editTrophy,
  };
}

/// Pure initial-route resolution (no Flutter / Firebase imports).
class AppRouter {
  AppRouter._();

  /// Friendly path aliases -> canonical route. Keys are lower-cased; matching
  /// is case-insensitive. `/admin` and its variants keep the OLD portal
  /// reachable, `/admin-portal-v2` etc. reach Admin Portal V2.
  static const Map<String, String> pathAliases = <String, String>{
    '/admin': AppRoutes.adminDashboard,
    '/admin-portal': AppRoutes.adminDashboard,
    '/admin_dashboard_v1': AppRoutes.adminDashboard,
    '/admin-portal-v2': AppRoutes.adminPortalV2,
    '/admin_v2': AppRoutes.adminPortalV2,
  };

  /// Normalise a raw route / path into a leading-slash, single-slash,
  /// no-trailing-slash form. Handles a full `#/route` fragment, a query string
  /// and duplicate slashes. Returns an empty string when there is nothing
  /// usable (root, blank, or a bare `#`).
  static String normalizePath(String? raw) {
    if (raw == null) return '';
    var p = raw.trim();
    if (p.isEmpty) return '';

    // A `#/route` fragment (or a full URL with one) — keep the route part.
    final hashIndex = p.indexOf('#');
    if (hashIndex >= 0) {
      p = hashIndex == 0 ? p.substring(1) : p.substring(0, hashIndex);
    }
    // Drop any query string.
    final queryIndex = p.indexOf('?');
    if (queryIndex >= 0) {
      p = p.substring(0, queryIndex);
    }
    if (p.isEmpty) return '';

    if (!p.startsWith('/')) p = '/$p';
    p = p.replaceAll(RegExp(r'/+'), '/');
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Resolve a friendly path alias to its canonical route, or `null` when the
  /// path is not an alias. Case-insensitive.
  static String? resolvePathAlias(String path) {
    if (path.isEmpty) return null;
    return pathAliases[path.toLowerCase()];
  }

  /// The route the app should boot into.
  ///
  /// Priority:
  ///   1. [hashRoute] — the engine's `defaultRouteName` (`#/route`), i.e. the
  ///      existing hash-deep-link behaviour, when it names a known route.
  ///   2. [browserPath] — a web path deep link (`/admin_portal_v2`), resolved
  ///      through [resolvePathAlias], when it names a known route.
  ///   3. [fallback] — the splash, so an ordinary launch is unchanged.
  static String resolveInitialRoute({
    String hashRoute = '',
    String browserPath = '',
    required bool Function(String route) isKnownRoute,
    String fallback = AppRoutes.splash,
  }) {
    final hash = normalizePath(hashRoute);
    if (hash.isNotEmpty && hash != '/' && isKnownRoute(hash)) {
      return hash;
    }

    final path = normalizePath(browserPath);
    if (path.isNotEmpty && path != '/') {
      final target = resolvePathAlias(path) ?? path;
      if (isKnownRoute(target)) return target;
    }

    return fallback;
  }
}
