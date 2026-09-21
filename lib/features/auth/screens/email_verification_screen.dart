import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../services/email_verification_service.dart';
import '../services/password_reset_cooldown.dart';

/// Email-verification gate (TODO #3).
///
/// Shown whenever a signed-in account with an unverified email address tries
/// to reach an authenticated surface (registration, email login, Google
/// sign-in, 2FA completion, or a cold launch through the splash screen).
///
/// Three ways forward:
///  * "I'VE VERIFIED — CONTINUE" reloads the Firebase user and, once
///    `emailVerified` is true, runs [onVerified] so the caller resumes its
///    normal routing.
///  * "RESEND EMAIL" re-dispatches the Firebase verification mail with a
///    60-second retry cooldown (each resend invalidates the previous link).
///  * an automatic poll every 3 seconds reloads the user and continues on its
///    own the moment verification lands, so the user can simply switch to
///    their inbox and come back.
///
/// "USE A DIFFERENT ACCOUNT" signs out and returns to the auth screen.
class EmailVerificationScreen extends StatefulWidget {
  /// Resumes the caller's normal routing once the email is verified.
  final VoidCallback onVerified;

  /// Overridable email for tests / previews; defaults to the live Firebase
  /// user's address.
  final String? emailOverride;

  /// Test seams mirroring the `AuthScreen` override pattern. Each defaults to
  /// the real Firebase Auth call when null.
  @visibleForTesting
  final Future<void> Function()? sendVerificationEmailOverride;
  @visibleForTesting
  final Future<bool> Function()? refreshVerificationStatusOverride;
  @visibleForTesting
  final Future<void> Function()? signOutOverride;

  const EmailVerificationScreen({
    super.key,
    required this.onVerified,
    this.emailOverride,
    this.sendVerificationEmailOverride,
    this.refreshVerificationStatusOverride,
    this.signOutOverride,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  /// Poll cadence for the automatic verification check.
  static const Duration _pollInterval = Duration(seconds: 3);

  Timer? _pollTimer;
  Timer? _cooldownTimer;

  bool _isRefreshing = false;
  bool _isResending = false;
  bool _isSigningOut = false;
  DateTime? _cooldownUntil;

  String get _email =>
      widget.emailOverride ??
      (_currentUser()?.email ?? 'your email address');

  /// Null-safe current Firebase user.
  ///
  /// `FirebaseAuth.instance` throws `[core/no-app]` when Firebase has not been
  /// initialized (widget tests / cold-launch races), so the accessor is
  /// wrapped here to keep the screen renderable in those environments.
  User? _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _autoCheck());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Reloads the Firebase user and continues automatically when the email has
  /// been verified. Silent on failure (offline) — the next tick retries.
  Future<void> _autoCheck() async {
    if (!mounted || _isRefreshing) return;
    try {
      final verified = await _refreshStatus();
      if (!mounted) return;
      if (verified) {
        _pollTimer?.cancel();
        widget.onVerified();
      }
    } catch (_) {
      // Offline / transient — the periodic timer retries.
    }
  }

  Future<bool> _refreshStatus() async {
    final override = widget.refreshVerificationStatusOverride;
    if (override != null) return override();
    return EmailVerificationService.instance.checkVerified();
  }

  /// Manual "I'VE VERIFIED" — reloads and continues when verified, otherwise
  /// shows guidance.
  Future<void> _handleVerifiedPressed() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final verified = await _refreshStatus();
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      if (verified) {
        _pollTimer?.cancel();
        widget.onVerified();
      } else {
        _showSnack(
          'We could not confirm your verification yet. Open the link in your '
          'inbox, then tap this button again.',
          background: Colors.orange,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      _showSnack('Could not check your status: $e', background: Colors.red);
    }
  }

  /// "RESEND EMAIL" — dispatches a fresh verification mail and engages the
  /// 60-second retry cooldown so the user cannot spam duplicate links.
  Future<void> _handleResendPressed() async {
    if (_isResending || _isCoolingDown) return;
    setState(() => _isResending = true);
    try {
      await _sendEmail();
      if (!mounted) return;
      setState(() => _isResending = false);
      _engageCooldown();
      _showSnack(
        'Verification email sent to $_email',
        background: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResending = false);
      _showSnack('Could not send the email: $e', background: Colors.red);
    }
  }

  Future<void> _sendEmail() async {
    final override = widget.sendVerificationEmailOverride;
    if (override != null) return override();
    await EmailVerificationService.instance.sendVerificationEmail();
  }

  /// Starts (or restarts) the 60-second resend cooldown and ticker.
  void _engageCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownUntil =
          PasswordResetCooldown.expiry(from: DateTime.now());
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (!_isCoolingDown) timer.cancel();
      });
    });
  }

  bool get _isCoolingDown {
    final until = _cooldownUntil;
    if (until == null) return false;
    return PasswordResetCooldown.isActive(now: DateTime.now(), until: until);
  }

  int get _cooldownRemaining {
    final until = _cooldownUntil;
    if (until == null) return 0;
    return PasswordResetCooldown.remainingSeconds(
      now: DateTime.now(),
      until: until,
    );
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      final override = widget.signOutOverride;
      if (override != null) {
        await override();
      } else {
        await FirebaseAuth.instance.signOut();
      }
    } catch (_) {
      // Best-effort: even if the network sign-out fails we still return to
      // the auth screen so the user is not stranded.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  void _showSnack(String message, {required Color background}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<ThemeController>() ?? ThemeController();

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Verify your email',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 72,
                  color: theme.accentColor,
                ),
                const SizedBox(height: 24),
                Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent verification to $_email',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: theme.subtitleColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open the link in that email to activate your account. '
                  'This screen checks automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: theme.subtitleColor),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  key: const ValueKey('iHaveVerifiedButton'),
                  onPressed: _isRefreshing ? null : _handleVerifiedPressed,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text("I'VE VERIFIED — CONTINUE"),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('resendVerificationButton'),
                  onPressed:
                      (_isResending || _isCoolingDown) ? null : _handleResendPressed,
                  icon: _isResending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _isCoolingDown
                        ? 'RESEND IN ${_cooldownRemaining}s'
                        : 'RESEND EMAIL',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textColor,
                    side: BorderSide(color: theme.accentColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                // Informational hint only — intentionally not a tappable
                // control (no mail-app plugin is added, per the task spec).
                Row(
                  key: const ValueKey('openEmailAppHint'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mail_outline,
                      size: 18,
                      color: theme.subtitleColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Open your email app to find the verification link',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.subtitleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  key: const ValueKey('useDifferentAccountButton'),
                  onPressed: _isSigningOut ? null : _handleSignOut,
                  child: const Text('USE A DIFFERENT ACCOUNT'),
                ),
                const SizedBox(height: 24),
                const CopyrightFooter.tight(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


