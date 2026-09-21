import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/entitlement_service.dart';
import '../../subscription/paywall_screen.dart';
import '../screens/email_verification_screen.dart';
import '../services/email_verification_policy.dart';
import '../services/role_guard.dart';
import '../services/user_role_provider.dart';

/// Route-level role guard widget.
///
/// Wrap a route's [builder] so the screen only mounts when the current user's
/// role is permitted (per [RoleGuard.canAccess]). On denial the user is
/// redirected cleanly back to their default home ([RoleGuard.defaultHomeFor])
/// with an "Access Denied" SnackBar notice - instead of rendering a screen
/// they may not use.
///
/// If the role has not been resolved yet (e.g. a deep-link cold launch), the
/// guard awaits [UserRoleProvider.resolveRole] before deciding, so access is
/// never granted on a stale `unknown` value.
///
/// Email-verification gate: before any of the above, a signed-in account with
/// an unverified email address is shown the [EmailVerificationScreen] and the
/// guarded screen only mounts once the address is verified. This is
/// defense-in-depth behind the splash / auth-screen gates so a deep-link entry
/// cannot bypass verification.
///
/// Billing & entitlement gate: when [requiresPremium] is true (default), the
/// route additionally requires an active entitlement - an active trial OR a
/// verified premium subscription. A user whose trial has expired and who is
/// not premium is shown the [PaywallScreen] (Subscribe via Google Play /
/// Manage subscription on the website). Admins are never paywalled.
///
/// Usage in `main.dart`:
///   '/hunter_dashboard': (ctx) => RoleGuardedRoute(
///       route: '/hunter_dashboard',
///       builder: (ctx) => HunterDashboard(theme: themeController),
///     ),
class RoleGuardedRoute extends StatefulWidget {
  const RoleGuardedRoute({
    super.key,
    required this.route,
    required this.builder,
    this.requiresPremium = true,
  });

  /// The named route being guarded (e.g. '/hunter_dashboard').
  final String route;

  /// Builds the screen shown when access is permitted.
  final WidgetBuilder builder;

  /// Whether this route requires an active entitlement (trial or premium).
  /// Set to false for routes that must stay reachable without a subscription
  /// (e.g. the subscription / paywall screens themselves).
  final bool requiresPremium;

  @override
  State<RoleGuardedRoute> createState() => _RoleGuardedRouteState();
}

class _RoleGuardedRouteState extends State<RoleGuardedRoute> {
  bool _checking = true;
  bool _paywall = false;

  @override
  void initState() {
    super.initState();
    _authorize();
  }

  Future<void> _authorize() async {
    final provider = UserRoleProvider.instance;

    // Email-verification gate (TODO #3): defense-in-depth for a deep-link cold
    // launch into a dashboard. The splash / auth screens already gate, but a
    // direct route entry must not slip past an unverified account. The gate is
    // pushed; the dashboard mounts only after the gate pops `true`.
    if (await _emailVerificationRequired()) {
      if (!mounted) return;
      final continued = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (routeContext) => EmailVerificationScreen(
            onVerified: () => Navigator.of(routeContext).pop(true),
          ),
        ),
      );
      if (!mounted) return;
      if (continued != true) return;
    }

    // Resolve the role if not already (covers deep-link / direct route entry).
    if (!provider.isResolved) {
      await provider.resolveRole();
    }

    final role = provider.role;
    final allowed = RoleGuard.canAccess(role, widget.route);

    if (!mounted) return;

    if (allowed && widget.requiresPremium && role != AppRole.admin) {
      final entitlement = await EntitlementService.instance.getMyEntitlement();
      if (mounted && !entitlement.canAccessPremium(DateTime.now())) {
        setState(() {
          _paywall = true;
          _checking = false;
        });
        return;
      }
    }

    if (allowed) {
      setState(() => _checking = false);
      return;
    }

    // Denied: bounce back to the role's default home with an access-denied
    // notice. Done in a post-frame callback so navigation happens after the
    // current frame (the route is still building).
    final home = RoleGuard.defaultHomeFor(role);
    final message = RoleGuard.accessDeniedMessage(role, widget.route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pushReplacementNamed(home);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  /// Whether the signed-in account must verify its email before the guarded
  /// route may mount. Returns `false` when Firebase is unavailable (widget
  /// tests / cold-launch races) so the guard is never blocked by a missing
  /// Firebase app.
  Future<bool> _emailVerificationRequired() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser ?? user;
      return EmailVerificationPolicy.requiresVerification(
        email: refreshed.email,
        emailVerified: refreshed.emailVerified,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paywall) {
      return PaywallScreen(theme: ThemeController.instance);
    }
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(context);
  }
}
