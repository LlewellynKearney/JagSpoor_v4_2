import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../../core/theme/app_theme.dart';
import '../admin/services/admin_auth_guard.dart';
import '../hunter_mode/hunter_profile_screen.dart';
import '../hunter_mode/services/hunter_profile_completeness.dart';
import 'services/auth_repository.dart';
import 'services/role_guard.dart';
import 'services/user_role_provider.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isAdmin = false;
  bool _resolving = true;

  /// Guards against a double-tap issuing two role writes / two navigations.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resolveAdmin();
    _skipIfRoleAlreadyAssigned();
  }

  /// Defense-in-depth for direct route entry / a stale navigation stack: if
  /// the account already carries a permanent role, bounce straight to the
  /// matching dashboard instead of asking again. Post-auth routing normally
  /// prevents this screen from being reached at all for a role-bearing
  /// account; this covers a deep link or a route pushed before the role
  /// resolved.
  Future<void> _skipIfRoleAlreadyAssigned() async {
    try {
      // Never race an in-flight selection: once the user has confirmed a role
      // their own write + navigation owns the outcome.
      if (_saving) return;
      final uid = AuthRepository.instance.currentUid;
      if (uid == null) return;
      final role = await AuthRepository.instance.storedRole(uid);
      if (!mounted || _saving) return;
      if (role == AppRole.unknown || role == AppRole.admin) return;
      final route = RoleGuard.defaultHomeFor(role);
      if (route.isEmpty) return;
      UserRoleProvider.instance.setRole(role);
      Navigator.pushReplacementNamed(context, route);
    } catch (e) {
      debugPrint('RoleSelectionScreen: role skip check failed: $e');
    }
  }

  Future<void> _resolveAdmin() async {
    final admin = await AdminAuthGuard.instance.isCurrentUserAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _resolving = false;
    });
  }

  /// Handles a Hunter/Outfitter card tap.
  ///
  /// Admins/Superusers bypass the single-role confirmation modal entirely and
  /// never have a permanent role written to their `users/{uid}` document —
  /// they are routed straight into the requested mode as a multi-profile
  /// preview. Regular accounts see the exclusivity warning and, on confirm,
  /// have their chosen role locked in to Firestore before navigating.
  ///
  /// The write is VERIFIED (see [AuthRepository.saveRole]): a role that does
  /// not actually land leaves the account role-less and bounces the user back
  /// here on every sign-in, so a failure surfaces an error snackbar and keeps
  /// the user on this screen to retry rather than navigating onward.
  Future<void> _confirmAndSelectRole({
    required String role,
    required String routeName,
  }) async {
    if (_saving) return;

    // Resolve admin status authoritatively before deciding on the bypass —
    // the `_isAdmin` UI flag is still `false` while the initial async
    // resolution is in flight, so a tap during that window must re-check.
    final isAdmin = _resolving
        ? await AdminAuthGuard.instance.isCurrentUserAdmin()
        : _isAdmin;

    // Admins get seamless multi-profile access — no dialog, no role write.
    if (isAdmin) {
      // Cache the admin role so the dashboard route guards admit them.
      UserRoleProvider.instance.setRole(AppRole.admin);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, routeName);
      return;
    }

    final uid = AuthRepository.instance.currentUid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to select a role.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await _showRoleExclusivityDialog(role) ?? false;
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);

    // Make sure the profile document exists before the role is written to it.
    // A missing document is the other half of the reported defect: 9 of 25
    // registered users had no role because nothing guaranteed the doc.
    await AuthRepository.instance.ensureUserDocument(
      uid: uid,
      email: AuthRepository.instance.currentEmail,
    );

    // Persist the role choice and VERIFY it landed. A silent failure here is
    // exactly what left accounts stuck on this screen on every sign-in.
    try {
      await AuthRepository.instance.saveRole(uid: uid, role: role);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save your role: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // Analytics: record the completed selection (best-effort — never blocks
    // onboarding if the plugin / Firebase Analytics is unavailable).
    unawaited(_logRoleSelected(role));

    // Cache the chosen role so the destination dashboard's route guard admits
    // the user without a re-fetch (the Firestore write above may not be
    // readable for a few hundred ms).
    UserRoleProvider.instance.setRole(
      role == 'outfitter' ? AppRole.outfitter : AppRole.hunter,
    );

    // Mandatory onboarding gate for hunters: a brand-new hunter has no
    // profile yet, so redirect them to the Hunter Profile screen to
    // complete Name / Surname / contact before reaching the dashboard.
    if (role == 'hunter') {
      final status = await HunterProfileCompleteness.instance.statusFor(uid);
      if (!status.isComplete && mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                HunterProfileScreen(theme: ThemeController.instance),
          ),
          (_) => false,
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pushReplacementNamed(context, routeName);
  }

  /// Logs the `role_selected` analytics event. Best-effort: a missing Firebase
  /// app (`[core/no-app]` in a widget test / cold-launch race) is swallowed.
  Future<void> _logRoleSelected(String role) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: 'role_selected',
        parameters: {'role': role},
      );
    } catch (e) {
      debugPrint('RoleSelectionScreen: role_selected log failed: $e');
    }
  }

  Future<bool?> _showRoleExclusivityDialog(String role) {
    final roleLabel = role == 'outfitter' ? 'Outfitter' : 'Hunter';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Operational Role'),
        content: Text(
          'Please note: Regular accounts are strictly single-role. You can '
          'only be registered as EITHER a Hunter OR an Outfitter. Once set, '
          'you will not be able to switch between profiles (only the JagSpoor '
          'Admin/Superuser has system-wide access across all profiles).\n\n'
          'Are you sure you want to proceed as a $roleLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm & Proceed'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SELECT OPERATIONAL PROFILE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 40.0),
              RoleCard(
                title: 'HUNTER MODE',
                description:
                    'Tactical field utilities, digital safe, ballistic processing, and logs.',
                icon: Icons.gps_fixed_sharp,
                themeData: theme,
                onTap: () => _confirmAndSelectRole(
                    role: 'hunter', routeName: '/hunter_dashboard'),
              ),
              const SizedBox(height: 20.0),
              RoleCard(
                title: 'OUTFITTER MODE',
                description:
                    'Game farm management ops, client tracking, lodging, and fleets.',
                icon: Icons.business_center_sharp,
                themeData: theme,
                onTap: () => _confirmAndSelectRole(
                    role: 'outfitter', routeName: '/outfitter_dashboard'),
              ),
              // Admin portal entry point — only rendered for admins
              // (custom claim admin == true, users/{uid}.role == 'admin',
              // outfitters/{uid}.role == 'admin', or the admin@jag-spoor.co.za
              // allow-list). Admins skip the role-exclusivity dialog since they
              // have system-wide access across all profiles.
              if (_isAdmin) ...[
                const SizedBox(height: 20.0),
                RoleCard(
                  title: 'ADMIN PORTAL',
                  description:
                      'Master analytics dashboard, account management, and bulk imports.',
                  icon: Icons.admin_panel_settings_sharp,
                  themeData: theme,
                  onTap:
                      () => Navigator.pushReplacementNamed(
                        context,
                        '/admin_dashboard',
                      ),
                ),
              ] else if (_resolving) ...[
                const SizedBox(height: 20.0),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RoleCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final ThemeData themeData; // Explicitly declared field
  final VoidCallback onTap;

  // Fixed: Named parameter explicitly mapped here to remove parameter errors
  const RoleCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.themeData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          border: Border.all(
            color: themeData.colorScheme.primary.withOpacity(0.4),
            width: 1.5,
          ),
          // ignore: deprecated_member_use
          color: themeData.colorScheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40.0, color: themeData.colorScheme.primary),
            const SizedBox(width: 20.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: themeData.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.0,
                      // ignore: deprecated_member_use
                      color: themeData.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
