import 'user_role_provider.dart';

/// Pure, dependency-free role-based access control rules.
///
/// Keeping the policy in a single testable object (no Firebase / Flutter
/// imports) lets the guard behaviour be fully unit-tested without emulators.
/// The [UserRoleProvider] owns *who* the user is; [RoleGuard] owns *what they
/// may do*.
class RoleGuard {
  RoleGuard._();

  /// Routes reserved for platform admins. Any non-admin attempting to open one
  /// is redirected to their default home with an access-denied notice.
  static const Set<String> adminOnlyRoutes = {
    '/admin_dashboard',
  };

  /// Role-scoped dashboard routes — a user may only open the dashboard that
  /// matches their role (admins may open any).
  static const Map<AppRole, String> roleHomeRoutes = {
    AppRole.admin: '/admin_dashboard',
    AppRole.outfitter: '/outfitter_dashboard',
    AppRole.hunter: '/hunter_dashboard',
  };

  /// Returns `true` when [role] is permitted to navigate to [route].
  ///
  /// Policy:
  ///   - Admin-only routes require [AppRole.admin].
  ///   - The Hunter / Outfitter dashboards require the matching role (or
  ///     admin, who may preview any mode).
  ///   - Every other route (forms, detail screens, license scanner, etc.) is
  ///     not role-scoped at this layer and defaults to allowed.
  static bool canAccess(AppRole role, String route) {
    if (adminOnlyRoutes.contains(route)) {
      return role == AppRole.admin;
    }
    if (route == '/hunter_dashboard') {
      return role == AppRole.admin || role == AppRole.hunter;
    }
    if (route == '/outfitter_dashboard') {
      return role == AppRole.admin || role == AppRole.outfitter;
    }
    return true;
  }

  /// The default landing route for [role] — where an unauthorized user is
  /// bounced back to. [AppRole.unknown] routes to role selection so a user
  /// whose role couldn't be resolved is not silently dropped on a dashboard
  /// they may not access.
  static String defaultHomeFor(AppRole role) {
    return roleHomeRoutes[role] ?? '/role_selection';
  }

  /// Only admins may use the instant mode switcher (Hunter ↔ Outfitter ↔
  /// Admin). Hunters and outfitters are single-role and locked to their mode.
  static bool canSwitchModes(AppRole role) => role == AppRole.admin;

  /// The notice shown in the access-denied SnackBar for [route]. Tailored per
  /// route so the message is actionable.
  static String accessDeniedMessage(AppRole role, String route) {
    if (adminOnlyRoutes.contains(route)) {
      return 'Access Denied: Admin privileges required.';
    }
    if (route == '/hunter_dashboard') {
      return 'Access Denied: Hunter Mode is for registered hunters only.';
    }
    if (route == '/outfitter_dashboard') {
      return 'Access Denied: Outfitter Management requires an outfitter account.';
    }
    return 'Access Denied: You do not have permission to view this screen.';
  }
}
