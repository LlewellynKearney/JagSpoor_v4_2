import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/auth/role_selection_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/admin/services/admin_auth_guard.dart';
import 'theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final ThemeController theme;

  const SplashScreen({super.key, required this.theme});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();

    // Navigate after animation
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _navigateToNextScreen();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Dynamic boot routing — resolves the user's auth state AND assigned role
  /// to route directly to the correct shell, instead of forcing every signed-in
  /// user back to the role selection screen on every launch.
  ///
  ///   currentUser == null                 → AuthScreen (login / register)
  ///   admin (claim / email / role==admin) → /admin_dashboard
  ///   role == 'hunter'                     → /hunter_dashboard
  ///   role == 'outfitter'                  → /outfitter_dashboard
  ///   no role assigned yet (or fetch error)→ RoleSelectionScreen
  Future<void> _navigateToNextScreen() async {
    final user = FirebaseAuth.instance.currentUser;

    // Not authenticated — go to login / registration.
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AuthScreen(themedata: widget.theme)),
      );
      return;
    }

    // Admins route straight to the admin portal.
    try {
      final isAdmin = await AdminAuthGuard.instance.isCurrentUserAdmin();
      if (isAdmin) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/admin_dashboard');
        return;
      }
    } catch (_) {
      // Fall through to role lookup; admin status may also surface there.
    }

    // Resolve the assigned role from the users/{uid} profile.
    String? role;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      role = doc.data()?['role'] as String?;
    } catch (_) {
      // Offline / permission error: treat as unassigned so the user lands on
      // role selection rather than a blank screen.
      role = null;
    }

    if (!mounted) return;
    switch (role) {
      case 'hunter':
        Navigator.pushReplacementNamed(context, '/hunter_dashboard');
        break;
      case 'outfitter':
        Navigator.pushReplacementNamed(context, '/outfitter_dashboard');
        break;
      default:
        // No role assigned yet — let the user select their permanent role.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          body: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo — upscaled emblem so it displays prominent and
                  // high-resolution while Firebase auth / role checks run.
                  // Uses a fraction of the screen width so it scales gracefully
                  // across phone/tablet aspect ratios without cropping.
                  Image.asset(
                    'assets/app logo/logo1.png',
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: MediaQuery.of(context).size.width * 0.6,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  // App Name
                  Text(
                    'JAGSPOOR',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: widget.theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Loading indicator
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: widget.theme.accentColor,
                      strokeWidth: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
