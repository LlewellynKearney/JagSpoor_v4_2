import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../admin/services/admin_auth_guard.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isAdmin = false;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolveAdmin();
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
  Future<void> _confirmAndSelectRole(
      {required String role, required String routeName}) async {
    // Resolve admin status authoritatively before deciding on the bypass —
    // the `_isAdmin` UI flag is still `false` while the initial async
    // resolution is in flight, so a tap during that window must re-check.
    final isAdmin = _resolving
        ? await AdminAuthGuard.instance.isCurrentUserAdmin()
        : _isAdmin;

    // Admins get seamless multi-profile access — no dialog, no role write.
    if (isAdmin) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, routeName);
      return;
    }

    final confirmed = await _showRoleExclusivityDialog(role) ?? false;
    if (!confirmed || !mounted) return;

    // Persist the role choice so it is locked in (single-role accounts).
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({
          'role': role,
          'roleSetAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-fatal: proceed to the dashboard even if the role write fails
        // (e.g. offline). The selection still navigates the user onward.
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, routeName);
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
