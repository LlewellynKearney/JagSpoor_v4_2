import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/auth/role_selection_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/services/user_role_provider.dart';
import '../features/hunter_mode/hunter_profile_screen.dart';
import '../features/hunter_mode/services/hunter_profile_completeness.dart';
import 'theme/app_theme.dart';
import 'widgets/copyright_footer.dart';

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
  /// The resolved role is cached in [UserRoleProvider] so the route guards on
  /// the dashboard routes read a single consistent value.
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

    // Resolve the role once here (cached for the route guards / dashboards).
    final role = await UserRoleProvider.instance.resolveRole(forceRefresh: true);

    // Self-heal a missing `outfitterId` self-link before entering outfitter
    // mode, so downstream owner-scoped Firestore rules (trophies, permits,
    // scanned_pricelists…) don't crash on a missing parameter.
    if (role == AppRole.outfitter) {
      await _ensureOutfitterSelfLink();
    }

    // Mandatory onboarding gate for hunters: a hunter whose Name / Surname /
    // contact detail are not yet saved to Firestore is redirected to the
    // Hunter Profile screen to complete onboarding before reaching the
    // dashboard. Admins and outfitters are not gated by this check.
    if (role == AppRole.hunter) {
      final status =
          await HunterProfileCompleteness.instance.statusFor(user.uid);
      if (!status.isComplete && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HunterProfileScreen(theme: widget.theme),
          ),
          (_) => false,
        );
        return;
      }
    }

    if (!mounted) return;
    switch (role) {
      case AppRole.admin:
        Navigator.pushReplacementNamed(context, '/admin_dashboard');
        break;
      case AppRole.hunter:
        Navigator.pushReplacementNamed(context, '/hunter_dashboard');
        break;
      case AppRole.outfitter:
        Navigator.pushReplacementNamed(context, '/outfitter_dashboard');
        break;
      case AppRole.unknown:
        // No role assigned yet / fetch error — let the user select their
        // permanent role.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
    }
  }

  /// Ensures the signed-in outfitter's `users/{uid}` document carries an
  /// `outfitterId` field equal to their own uid. Outfitter-mode Firestore
  /// collections (trophies, outfitter_venison_permits, scanned_pricelists) are all
  /// owner-scoped on
  /// `outfitterId == auth.uid`; a missing field would make every list query
  /// silently empty and every create get rejected server-side. Best-effort,
  /// non-fatal — failures don't block the boot route.
  Future<void> _ensureOutfitterSelfLink() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    try {
      final userDoc = await db.collection('users').doc(uid).get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      if (data['outfitterId'] != uid) {
        await db.collection('users').doc(uid).set({
          'outfitterId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      final outfitterDoc = await db.collection('outfitters').doc(uid).get();
      if (outfitterDoc.exists &&
          outfitterDoc.data()?['outfitterId'] != uid) {
        await db.collection('outfitters').doc(uid).set({
          'outfitterId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Non-fatal: proceed to the outfitter dashboard.
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
                  const SizedBox(height: 48),
                  const CopyrightFooter(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
