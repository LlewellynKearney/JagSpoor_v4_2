import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../authentication/services/auth_gate_service.dart';
import 'role_selection_screen.dart';
import 'screens/privacy_policy_screen.dart';

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
  final _authGateService = AuthGateService();

  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _keepMeSignedIn = false;
  bool _hasAcceptedPrivacyPolicy = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
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
          _navigateToRoleSelection();
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
        onVerified: _navigateToRoleSelection,
        onCancel: () {
          Navigator.pop(context);
          _authGateService.signOut();
          setState(() => _isLoading = false);
        },
      ),
    );
  }

  void _navigateToRoleSelection() {
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
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
      } else {
        // Create Firebase Auth user
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      );
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
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'EMAIL ADDRESS',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val!.isEmpty ? 'Enter email' : null,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
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
                  ],
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF3C2A21), // Dark walnut
            Color(0xFF5C4033), // Walnut brown
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFFE6A15C).withValues(alpha: 0.4),
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
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Continue with Google',
                  style: TextStyle(
                    color: Colors.white,
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
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0xFFE6A15C), width: 2),
          left: BorderSide(color: Color(0xFFE6A15C), width: 1),
          right: BorderSide(color: Color(0xFFE6A15C), width: 1),
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Header
            const Row(
              children: [
                Icon(Icons.security, color: Color(0xFFE6A15C), size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'TWO-FACTOR AUTHENTICATION',
                    style: TextStyle(
                      color: Color(0xFFE6A15C),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Enter the 6-digit security code sent to your verified phone number.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            
            // OTP Input
            TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '------',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 28,
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: const Color(0xFF2A2F2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: const Color(0xFFE6A15C).withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE6A15C), width: 2),
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
                backgroundColor: const Color(0xFFE6A15C),
                foregroundColor: Colors.black,
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
