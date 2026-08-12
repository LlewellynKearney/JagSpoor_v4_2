import 'package:flutter/material.dart';
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
                onTap:
                    () => Navigator.pushReplacementNamed(
                      context,
                      '/hunter_dashboard',
                    ),
              ),
              const SizedBox(height: 20.0),
              RoleCard(
                title: 'OUTFITTER MODE',
                description:
                    'Game farm management ops, client tracking, lodging, and fleets.',
                icon: Icons.business_center_sharp,
                themeData: theme,
                onTap:
                    () => Navigator.pushReplacementNamed(
                      context,
                      '/outfitter_dashboard',
                    ),
              ),
              // Admin portal entry point — only rendered for admins
              // (custom claim admin == true, users/{uid}.role == 'admin',
              // outfitters/{uid}.role == 'admin', or the admin@jag-spoor.co.za
              // allow-list).
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
