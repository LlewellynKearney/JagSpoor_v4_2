import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../authentication/services/auth_gate_service.dart';
import 'role_selection_screen.dart';
import 'screens/privacy_policy_screen.dart';
import '../hunter_mode/hunter_profile_screen.dart';
import '../hunter_mode/services/hunter_profile_completeness.dart';
import 'services/user_role_provider.dart';
import 'services/password_reset_action_code_settings.dart';
import 'services/password_reset_cooldown.dart';
import 'services/autofill_credential_prompter.dart';

class AuthScreen extends StatefulWidget {
  final ThemeController themedata;

  const AuthScreen({super.key, required this.themedata});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  // Lazy: `AuthGateService` eagerly resolves `FirebaseAuth.instance`, which
  // throws `[core/no-app]` before Firebase initializes (cold-launch race /
  // widget tests). Defer construction to first use (Google sign-in / 2FA).
  AuthGateService get _authGateService => AuthGateService();

  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _keepMeSignedIn = false;
  bool _hasAcceptedPrivacyPolicy = false;
  bool _isLoading = false;

  // Password-reset retry cooldown: after a successful reset send (or a
  // Firebase `too-many-requests` rejection) the "Forgot Password?" dialog
  // disables its send button for [PasswordResetCooldown.defaultCooldownSeconds]
  // seconds to prevent spamming duplicate reset tokens (each new token
  // invalidates the previous link and re-queues an email delivery, which is
  // the perceived "email delay"). `_resetCooldownUntil` is the single source
  // of truth (an absolute timestamp); the dialog owns its own 1s countdown
  // timer that reads this value.
  DateTime? _resetCooldownUntil;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Engages the password-reset retry cooldown for the default window. The
  /// dialog's own countdown timer reads [_resetCooldownUntil] to render the
  /// live "Resend in Ns" label.
  void _engageResetCooldown() {
    _resetCooldownUntil = PasswordResetCooldown.expiry(from: DateTime.now());
  }

  /// Handle Google Sign-In
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final credential = await _authGateService.signInWithGoogle();

      if (credential != null) {
        // Check if user needs 2FA
        if (_requires2FA(credential.user)) {
          _show2FAVerificationSheet();
        } else {
          _routeAfterAuth();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Check if user requires 2FA (outfitter/enterprise accounts)
  bool _requires2FA(User? user) {
    // For now, check if user has phone number linked
    // In production, check Firestore user profile for 2FA flag
    return user?.phoneNumber != null;
  }

  /// Show 2FA Verification Bottom Sheet
  void _show2FAVerificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TwoFAVerificationSheet(
        onVerified: _routeAfterAuth,
        onCancel: () {
          Navigator.pop(context);
          _authGateService.signOut();
          setState(() => _isLoading = false);
        },
      ),
    );
  }

  /// Post-auth role-aware routing — the direct role bypass.
  ///
  /// Resolves the signed-in user's role (cached for the route guards) and
  /// routes straight to the matching dashboard, bypassing the
  /// "Select Operational Profile" screen entirely for users with a permanent
  /// single role:
  ///   - `outfitter` → `/outfitter_dashboard` (after self-linking
  ///     `outfitterId = uid` if missing — see [_ensureOutfitterSelfLink])
  ///   - `hunter`    → mandatory-profile check: if Name / Surname / a
  ///     contact detail are missing, redirect to the Hunter Profile screen
  ///     to complete onboarding; otherwise `/hunter_dashboard`.
  ///   - `admin`     → `/admin_dashboard`
  ///   - `unknown` / dual-role / unassigned → [RoleSelectionScreen]
  ///
  /// This mirrors [SplashScreen._navigateToNextScreen] so a returning
  /// outfitter/hunter is never bounced through role selection on every
  /// login. Role selection is strictly reserved for new sign-ups, dual-role
  /// accounts, and `unassigned`/`admin` profiles.
  Future<void> _routeAfterAuth() async {
    // Resolve the role ONCE (forceRefresh to bypass any stale cache from a
    // previous session) and cache it so the destination route guard admits
    // the user without a re-fetch.
    final role =
        await UserRoleProvider.instance.resolveRole(forceRefresh: true);

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
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final status =
            await HunterProfileCompleteness.instance.statusFor(user.uid);
        if (!status.isComplete && mounted) {
          setState(() => _isLoading = false);
          final missing = status.missingSummary;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => HunterProfileScreen(theme: widget.themedata),
            ),
            (_) => false,
          );
          if (missing.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Please complete your profile before continuing. $missing',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

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
        // No permanent single role — let the user pick / preview a mode.
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
  /// silently empty and every create get rejected server-side. This is a
  /// best-effort, non-fatal write — if it fails (e.g. offline / rules), the
  /// user still proceeds to the dashboard and the field can be backfilled
  /// later. Also mirrors the field onto the `outfitters/{uid}` doc when it
  /// exists (the enterprise record keyed by uid).
  Future<void> _ensureOutfitterSelfLink() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    try {
      final userDoc = await db.collection('users').doc(uid).get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      final storedOutfitterId = data['outfitterId'];

      // Self-link is only needed when the field is absent or not yet
      // pointing at the user's own uid.
      if (storedOutfitterId != uid) {
        await db.collection('users').doc(uid).set({
          'outfitterId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Mirror the self-link onto the enterprise record if it exists (the
      // `outfitters/{uid}` doc is the canonical outfitter profile; many
      // downstream reads look it up by uid).
      final outfitterDoc = await db.collection('outfitters').doc(uid).get();
      if (outfitterDoc.exists &&
          outfitterDoc.data()?['outfitterId'] != uid) {
        await db.collection('outfitters').doc(uid).set({
          'outfitterId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Non-fatal: proceed to the outfitter dashboard. The self-link is a
      // best-effort hardening; the dashboard's own queries surface errors
      // gracefully and the field can be backfilled later.
    }
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    // POPIA Compliance: Block registration until privacy policy is accepted
    if (!_isLoginMode && !_hasAcceptedPrivacyPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submission Blocked: You must read and accept the Privacy & POPIA Policy before creating an account.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isLoginMode) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        // Successful login — commit the AutofillGroup context so the native
        // credential manager (Android Credential Manager / iOS Keychain)
        // prompts to save the email + password.
        AutofillCredentialPrompter.promptSaveCredentials();
      } else {
        // Create Firebase Auth user
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // Successful registration — commit the AutofillGroup context so the
        // native credential manager prompts to save the new credentials.
        AutofillCredentialPrompter.promptSaveCredentials();

        // Create Firestore user document
        final user = userCredential.user;
        if (user != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'email': email,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          } catch (firestoreError) {
            // Log Firestore error but don't block registration
            // User can still proceed, profile can be created later
          }
        }

        setState(() => _isLoading = false);

        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Registration successful. Welcome to Jagspoor!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      // Sign-in path: resolve the stored role and route directly to the
      // matching dashboard, bypassing role selection for users who already
      // have a permanent single role (outfitter / hunter / admin).
      await _routeAfterAuth();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Auth Error: ${_firebaseAuthErrorMessage(e)}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Firestore Error: ${e.message ?? "Permission denied or network error"}',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _firebaseAuthErrorMessage(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in or reset your password.';
      case 'weak-password':
        return 'Password too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Contact support.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support for help.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      default:
        return exception.message ?? 'Authentication failed. Please try again.';
    }
  }

  /// "Forgot Password?" flow: prompts for the email address (pre-filled from
  /// the login email field when present) and sends a Firebase password reset
  /// email with explicit [ActionCodeSettings] (deep link + in-app handling +
  /// package pinning) so the reset email dispatches promptly and resolves to
  /// the installed app. On success the dialog enters a 60-second retry
  /// cooldown (countdown shown on the send button) to prevent spamming
  /// duplicate reset tokens. Shows a clear in-dialog confirmation on success
  /// or a precise error on failure.
  Future<void> _showForgotPasswordDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PasswordResetDialog(
        initialEmail: _emailController.text.trim(),
        cooldownUntil: _resetCooldownUntil,
        onSend: (email) async {
          await FirebaseAuth.instance.sendPasswordResetEmail(
            email: email,
            actionCodeSettings: PasswordResetActionCodeSettings.build(),
          );
        },
        onCooldownEngaged: _engageResetCooldown,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              // Grouping the email + password fields in a single
              // `AutofillGroup` lets the platform treat them as one
              // credential set: autofill fills both together, and
              // `TextInput.finishAutofillContext()` (called on successful
              // auth) commits the group so the native credential manager
              // offers to save them.
              child: AutofillGroup(
                child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Logo
                    Center(
                      child: Image.asset(
                        'assets/app logo/logo1.png',
                        width: 140,
                        height: 140,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Text(
                      _isLoginMode ? 'JAGSPOOR LOGIN' : 'JAGSPOOR REGISTER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    TextFormField(
                      key: const ValueKey('loginEmailField'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      // Both hints: Android Credential Manager keys on
                      // `username`, iOS Keychain on `email`.
                      autofillHints: const [
                        AutofillHints.email,
                        AutofillHints.username,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'EMAIL ADDRESS',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val!.isEmpty ? 'Enter email' : null,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      key: const ValueKey('loginPasswordField'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      // `password` for sign-in, `newPassword` for sign-up so
                      // the platform stores the credential in the right flow.
                      autofillHints:
                          _isLoginMode
                              ? const [AutofillHints.password]
                              : const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'SECURE PIN / PASSWORD',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        ),
                      ),
                      validator:
                          (val) => val!.isEmpty ? 'Enter password' : null,
                    ),
                    // "Forgot Password?" reset link — shown on the login card,
                    // directly below the password field.
                    if (_isLoginMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _showForgotPasswordDialog,
                          icon: const Icon(Icons.lock_reset, size: 18),
                          label: const Text(
                            'Forgot Password?',
                            style: TextStyle(fontFamily: 'Mono', fontSize: 12.0),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12.0),
                    CheckboxListTile(
                      title: const Text(
                        'KEEP ME SIGNED IN',
                        style: TextStyle(fontFamily: 'Mono', fontSize: 12.0),
                      ),
                      value: _keepMeSignedIn,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged:
                          (val) =>
                              setState(() => _keepMeSignedIn = val ?? false),
                    ),
                    // POPIA Compliance: Privacy Policy acceptance checkbox (registration only)
                    if (!_isLoginMode) ...[
                      const SizedBox(height: 16.0),
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                _hasAcceptedPrivacyPolicy
                                    ? Colors.green.withValues(alpha: 0.5)
                                    : theme.colorScheme.primary.withValues(
                                      alpha: 0.3,
                                    ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _hasAcceptedPrivacyPolicy,
                              onChanged: (bool? value) {
                                setState(() {
                                  _hasAcceptedPrivacyPolicy = value ?? false;
                                });
                              },
                              activeColor: Colors.green,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) =>
                                                const PrivacyPolicyScreen(),
                                      ),
                                    );
                                  },
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontFamily: 'Mono',
                                        fontSize: 11.0,
                                        color: theme.colorScheme.onSurface,
                                        height: 1.3,
                                      ),
                                      children: [
                                        const TextSpan(
                                          text: 'I have read and accept the ',
                                        ),
                                        TextSpan(
                                          text:
                                              'Compliant Privacy & POPIA Policy',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: ' (Required for registration)',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_hasAcceptedPrivacyPolicy)
                        Container(
                          margin: const EdgeInsets.only(top: 8.0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Policy Accepted',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 24.0),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: const BeveledRectangleBorder(),
                      ),
                      onPressed: _isLoading ? null : _handleAuth,
                      child:
                          _isLoading
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text(
                                'AUTHENTICATE GATEWAY',
                                style: TextStyle(fontFamily: 'Mono'),
                              ),
                    ),
                    const SizedBox(height: 12.0),
                    
                    // Google Sign-In Button
                    _buildGoogleSignInButton(),
                    
                    const SizedBox(height: 16.0),
                    TextButton(
                      onPressed:
                          () => setState(() => _isLoginMode = !_isLoginMode),
                      child: Text(
                        _isLoginMode
                            ? 'SWITCH TO REGISTRATION'
                            : 'SWITCH TO LOGIN',
                        style: const TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    const CopyrightFooter(),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Premium Google Sign-In Button
  Widget _buildGoogleSignInButton() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.85),
            accent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleGoogleSignIn,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Official Google "G" logo (public-domain SVG, Google brand
                // colors). Per Google brand guidelines the full-color G sits on
                // a white background so the colors render correctly.
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: SvgPicture.asset(
                      'assets/images/google_logo.svg',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2FA SMS OTP Verification Bottom Sheet
class _TwoFAVerificationSheet extends StatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onCancel;

  const _TwoFAVerificationSheet({
    required this.onVerified,
    required this.onCancel,
  });

  @override
  State<_TwoFAVerificationSheet> createState() => _TwoFAVerificationSheetState();
}

class _TwoFAVerificationSheetState extends State<_TwoFAVerificationSheet> {
  final _otpController = TextEditingController();
  final _authGateService = AuthGateService();
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) {
      setState(() => _errorMessage = 'Please enter 6-digit code');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final credential = await _authGateService.verifySMSOTP(
        verificationId: _otpController.text,
        smsCode: _otpController.text,
      );

      if (credential != null) {
        if (!mounted) return;
        Navigator.pop(context);
        widget.onVerified();
      } else {
        setState(() {
          _errorMessage = 'Invalid verification code';
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed: $e';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: accent, width: 2),
          left: BorderSide(color: accent, width: 1),
          right: BorderSide(color: accent, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Header
            Row(
              children: [
                Icon(Icons.security, color: accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'TWO-FACTOR AUTHENTICATION',
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Enter the 6-digit security code sent to your verified phone number.',
              style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // OTP Input
            TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '------',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontSize: 28,
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: accent.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accent, width: 2),
                ),
              ),
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),

            // Verify Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isVerifying ? null : _verifyOTP,
              child: _isVerifying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'VERIFY IDENTITY',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Cancel Button
            TextButton(
              onPressed: widget.onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.textTheme.bodySmall?.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Self-contained "Forgot Password?" dialog that owns its own 1-second
/// countdown timer for the retry cooldown.
///
/// The dialog sends the password reset email through [onSend] (so the actual
/// Firebase call is injectable for testing / single-source configuration),
/// engages the cooldown via [onCooldownEngaged] on success and via
/// [onTooManyRequests] on a Firebase `too-many-requests` rejection, and reads
/// the absolute cooldown expiry ([cooldownUntil], captured at open time) to
/// render the live "Resend in Ns" countdown. The send button is disabled and
/// the email field is locked while the cooldown is active, preventing
/// duplicate reset-token requests that cause email delivery delays.
class _PasswordResetDialog extends StatefulWidget {
  final String initialEmail;
  final DateTime? cooldownUntil;
  final Future<void> Function(String email) onSend;
  final VoidCallback onCooldownEngaged;

  const _PasswordResetDialog({
    required this.initialEmail,
    required this.cooldownUntil,
    required this.onSend,
    required this.onCooldownEngaged,
  });

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  late final TextEditingController _emailController;
  Timer? _countdownTimer;
  int _remaining = 0;
  bool _sending = false;
  bool _confirmed = false;
  String? _errorMsg;

  /// Absolute cooldown expiry. Initialized from the parent's value (so a
  /// re-opened dialog inherits an in-progress cooldown) and updated locally
  /// when this dialog's own send succeeds or hits a rate-limit. Owned here
  /// (not read from the parent) so the live countdown reflects the cooldown
  /// this dialog just engaged without depending on a parent rebuild.
  DateTime? _cooldownUntil;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _cooldownUntil = widget.cooldownUntil;
    _syncRemaining();
    _maybeStartTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  bool get _cooldownActive =>
      _cooldownUntil != null &&
      PasswordResetCooldown.isActive(
        now: DateTime.now(),
        until: _cooldownUntil!,
      );

  /// Engages the cooldown both locally (drives this dialog's countdown) and
  /// in the parent (so a freshly re-opened dialog inherits the in-progress
  /// cooldown and the entry button can reflect it).
  void _engageCooldown() {
    _cooldownUntil = PasswordResetCooldown.expiry(from: DateTime.now());
    widget.onCooldownEngaged();
    _syncRemaining();
    _maybeStartTimer();
  }

  void _syncRemaining() {
    if (_cooldownUntil == null) {
      _remaining = 0;
      return;
    }
    _remaining = PasswordResetCooldown.remainingSeconds(
      now: DateTime.now(),
      until: _cooldownUntil!,
    );
  }

  void _maybeStartTimer() {
    if (!_cooldownActive) return;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemaining();
      if (_remaining <= 0) {
        _countdownTimer?.cancel();
        if (mounted) setState(() {});
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  String get _buttonLabel {
    if (_cooldownActive) return 'Resend in $_remaining s';
    return _confirmed ? 'Resend Reset Link' : 'Send Reset Link';
  }

  Future<void> _submit() async {
    if (_sending || _cooldownActive) return;

    final email = _emailController.text.trim();
    if (email.isEmpty ||
        !RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(email)) {
      setState(() => _errorMsg = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _sending = true;
      _errorMsg = null;
    });

    try {
      await widget.onSend(email);
      if (!mounted) return;
      _engageCooldown();
      setState(() {
        _sending = false;
        _confirmed = true;
        _errorMsg = null;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' =>
          'No account found for that email. Please check the address and try again.',
        'invalid-email' => 'That email address is not valid.',
        'too-many-requests' =>
          'Too many reset attempts. Please wait before trying again.',
        'invalid-continue-uri' =>
          'Reset link domain is not authorized. Please contact support.',
        _ => 'Could not send reset email: ${e.message ?? e.code}',
      };
      // On a Firebase rate-limit rejection, also engage the cooldown so the
      // user cannot hammer the endpoint while the rate limit is in effect.
      if (e.code == 'too-many-requests') {
        _engageCooldown();
      }
      setState(() {
        _sending = false;
        _errorMsg = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMsg = 'Could not send reset email: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _cooldownActive;
    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your account email and we will send you a secure link to '
            'reset your password.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            enabled: !active && !_sending,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          if (_confirmed && !active) ...[
            const SizedBox(height: 16),
            _banner(
              icon: Icons.check_circle,
              color: Colors.green,
              text: 'Reset link sent! Check your inbox (and spam folder) for '
                  'instructions.',
            ),
          ],
          if (active && _confirmed) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Please wait $_remaining s before requesting another link to '
                'avoid duplicate reset emails.',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            _banner(
              icon: Icons.error_outline,
              color: Colors.red,
              text: _errorMsg!,
            ),
          ],
          const SizedBox(height: 16),
          const CopyrightFooter(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: (active || _sending) ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(active ? Icons.timer_outlined : Icons.send),
          label: Text(_buttonLabel),
        ),
      ],
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
