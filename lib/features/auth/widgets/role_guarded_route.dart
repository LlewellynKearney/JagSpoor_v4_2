import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../screens/email_verification_screen.dart';
import '../services/email_verification_service.dart';
import '../services/role_guard.dart';
import '../services/user_role_provider.dart';

/// Route-level role guard widget.
///
/// Wrap a route's [builder] so the screen only mounts when the current user's
/// role is permitted (per [RoleGuard.canAccess]). On denial the user is
/// redirected cleanly back to their default home ([RoleGuard.defaultHomeFor])
/// with an "Access Denied" SnackBar notice — instead of rendering a screen
/// they may not use.
///
/// If the role has not been resolved yet (e.g. a deep-link cold launch), the
/// guard awaits [UserRoleProvider.resolveRole] before deciding, so access is
/// never granted on a stale `unknown` value.
///
/// Usage in `main.dart`:
///   '/admin_dashboard': (ctx) => RoleGuardedRoute(
///       route: '/admin_dashboard',
///       builder: (ctx) => AdminDashboardScreen(theme: themeController),
///     ),
class RoleGuardedRoute extends StatefulWidget {
  const RoleGuardedRoute({
    super.key,
    required this.route,
    required this.builder,
  });

  /// The named route being guarded (e.g. '/admin_dashboard').
  final String route;

  /// Builds the screen shown when access is permitted.
  final WidgetBuilder builder;

  @override
  State<RoleGuardedRoute> createState() => _RoleGuardedRouteState();
}

class _RoleGuardedRouteState extends State<RoleGuardedRoute> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _authorize();
  }

  Future<void> _authorize() async {
    // Defense-in-depth email-verification gate: an unverified email account
    // is bounced to the verification screen before the role check, so a
    // deep-link cold launch straight into a guarded dashboard cannot bypass
    // Firebase Auth's built-in email-verification flow. The verification
    // screen's continuation re-runs this authorization once verified.
    final verificationStatus =
        await EmailVerificationService.instance.currentStatus();
    if (verificationStatus.requiresVerification) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(
              theme: ThemeController.instance,
              onVerified: _authorize,
            ),
          ),
        );
      });
      return;
    }

    final provider = UserRoleProvider.instance;

    // Resolve the role if not already (covers deep-link / direct route entry).
    if (!provider.isResolved) {
      await provider.resolveRole();
    }

    final role = provider.role;
    final allowed = RoleGuard.canAccess(role, widget.route);

    if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(context);
  }
}
