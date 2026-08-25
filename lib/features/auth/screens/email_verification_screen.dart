import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../services/email_verification_service.dart';
import '../services/password_reset_cooldown.dart';

/// Email Verification gate screen.
///
/// Shown when a signed-in user's email address has not yet been verified via
/// Firebase Auth's built-in verification flow (the JagSpoor account mail is
/// hosted on the Afrihost mail platform). The screen:
///
///  1. Explains that a verification link was sent to the user's email.
///  2. Offers "RESEND VERIFICATION EMAIL" with a 60-second retry cooldown
///     (each resend invalidates the previous link and re-queues a delivery,
///     which is the root cause of the perceived email delay — the cooldown
///     prevents token spamming).
///  3. Offers "I'VE VERIFIED — REFRESH STATUS", which reloads the Firebase
///     user and, once `emailVerified` is true, invokes [onVerified] so the
///     caller resumes its normal routing (dashboard / role selection).
///  4. Offers "USE A DIFFERENT ACCOUNT", which signs the user out.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.theme,
    this.onVerified,
    this.sendVerificationEmailOverride,
    this.refreshVerificationStatusOverride,
    this.signOutOverride,
    this.statusResolverOverride,
  });

  final ThemeController theme;

  /// Continuation invoked once the account is verified. Callers resume their
  /// normal routing (e.g. the auth screen's role-aware routing, the splash
  /// boot routing, or role selection after registration). Defaults to
  /// restarting the boot flow at `/splash`.
  final VoidCallback? onVerified;

  /// Test seam: overrides [EmailVerificationService.sendVerificationEmail].
  @visibleForTesting
  final Future<void> Function()? sendVerificationEmailOverride;

  /// Test seam: overrides [EmailVerificationService.refreshStatus].
  @visibleForTesting
  final Future<bool> Function()? refreshVerificationStatusOverride;

  /// Test seam: overrides [EmailVerificationService.signOut].
  @visibleForTesting
  final Future<void> Function()? signOutOverride;

  /// Test seam: overrides [EmailVerificationService.currentStatus].
  @visibleForTesting
  final Future<EmailVerificationStatus> Function()? statusResolverOverride;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  EmailVerificationService get _service => EmailVerificationService.instance;

  String _email = '';
  bool _isResending = false;
  bool _isRefreshing = false;

  /// Absolute expiry of the active resend cooldown (null = no cooldown).
  DateTime? _resendCooldownUntil;

  /// 1-second ticker driving the "Resend in N s" countdown label.
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final override = widget.statusResolverOverride;
    final status =
        override != null ? await override() : await _service.currentStatus();
    if (!mounted) return;
    setState(() => _email = status.email);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  bool get _cooldownActive =>
      _resendCooldownUntil != null &&
      PasswordResetCooldown.isActive(
        now: DateTime.now(),
        until: _resendCooldownUntil!,
      );

  void _startCooldown() {
    _resendCooldownUntil =
        PasswordResetCooldown.expiry(from: DateTime.now());
    _cooldownTimer?.cancel();
    _cooldownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_cooldownActive) {
        _cooldownTimer?.cancel();
        _cooldownTimer = null;
        _resendCooldownUntil = null;
      }
      setState(() {});
    });
  }

  Future<void> _resend() async {
    if (_isResending || _cooldownActive) return;
    setState(() => _isResending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final override = widget.sendVerificationEmailOverride;
      if (override != null) {
        await override();
      } else {
        await _service.sendVerificationEmail();
      }
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _startCooldown();
      });
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Verification email sent! Check your inbox (and spam folder).',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _startCooldown(); // rate-limit safety net on failure too
      });
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not send the verification email right now. '
            'Please wait a moment and try again.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final override = widget.refreshVerificationStatusOverride;
    final verified =
        override != null ? await override() : await _service.refreshStatus();
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    if (verified) {
      final continuation = widget.onVerified;
      if (continuation != null) {
        continuation();
      } else {
        // Default continuation: restart the boot flow, which re-routes to
        // the correct destination now that the account is verified.
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/splash', (_) => false);
      }
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Email not verified yet. Please open the verification link in '
          'your inbox, then refresh again.',
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _useDifferentAccount() async {
    final override = widget.signOutOverride;
    if (override != null) {
      await override();
    } else {
      await _service.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final remaining = _resendCooldownUntil == null
        ? 0
        : PasswordResetCooldown.remainingSeconds(
            now: DateTime.now(),
            until: _resendCooldownUntil!,
          );

    return Scaffold(
      key: const ValueKey('emailVerificationScreen'),
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Card(
                  color: theme.cardColor,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.mark_email_read_rounded,
                          size: 64,
                          color: theme.accentColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'VERIFY YOUR EMAIL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: theme.textColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'JagSpoor account mail is hosted on our Afrihost '
                          'mail platform. We sent a verification link to:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.subtitleColor,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _email.isEmpty ? 'your email address' : _email,
                          key: const ValueKey('verificationEmailLabel'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Open the link in that email to activate your '
                          'account, then refresh your status below. '
                          'Verification is required before accessing core '
                          'app features.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.subtitleColor,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          key: const ValueKey('refreshVerificationButton'),
                          onPressed: _isRefreshing ? null : _refresh,
                          icon: _isRefreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_user_rounded),
                          label: Text(
                            _isRefreshing
                                ? 'CHECKING…'
                                : "I'VE VERIFIED — REFRESH STATUS",
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('resendVerificationButton'),
                          onPressed:
                              (_isResending || _cooldownActive) ? null : _resend,
                          icon: _isResending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.forward_to_inbox_rounded),
                          label: Text(
                            _cooldownActive
                                ? 'Resend in $remaining s'
                                : 'RESEND VERIFICATION EMAIL',
                          ),
                        ),
                        if (_cooldownActive) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Please wait $remaining s before requesting '
                            'another link to avoid duplicate emails.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextButton.icon(
                          key: const ValueKey('useDifferentAccountButton'),
                          onPressed: _useDifferentAccount,
                          icon: Icon(
                            Icons.logout_rounded,
                            color: theme.subtitleColor,
                          ),
                          label: Text(
                            'USE A DIFFERENT ACCOUNT',
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const CopyrightFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
