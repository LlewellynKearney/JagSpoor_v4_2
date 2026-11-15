import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_user_metrics.dart';
import '../models/admin_verification_target.dart';
import '../services/admin_verification_resend_service.dart';

/// The Admin Portal V2 "Email Verification" card (Users tab).
///
/// Surfaces the accounts that have NOT verified their email and lets a
/// platform admin re-send their verification email:
///
///   * **per-row RESEND** — a secure call to the admin-only
///     `resendVerificationEmail` callable (Admin SDK `generateEmailVerificationLink`
///     + SMTP delivery), then updates the audit flag on `users/{uid}`.
///   * **RESEND TO ALL UNVERIFIED (N)** — the same callable in bulk, capped at
///     [kAdminVerificationResendBatchLimit] per run (rate-limit protection),
///     behind a "Resend to X users?" confirmation dialog.
///
/// Admin-only: a non-admin sees the counts but every action is disabled and an
/// "Admin only" note is shown — the server re-checks privileges regardless, so
/// this is defense-in-depth.
class AdminVerificationCard extends StatefulWidget {
  final ThemeController theme;
  final List<AdminUserRecord> records;
  final bool isAdmin;

  /// Test seams: override the resend calls so a widget test never hits HTTP.
  final Future<ResendOutcome> Function(String uid)? resendOneOverride;
  final Future<BulkResendOutcome> Function(List<String> uids)? resendBulkOverride;

  const AdminVerificationCard({
    super.key,
    required this.theme,
    required this.records,
    required this.isAdmin,
    this.resendOneOverride,
    this.resendBulkOverride,
  });

  @override
  State<AdminVerificationCard> createState() => _AdminVerificationCardState();
}

class _AdminVerificationCardState extends State<AdminVerificationCard> {
  /// uid -> in-flight (per-row spinner).
  final Set<String> _busyUids = {};

  /// Whether the bulk action is in flight.
  bool _bulkBusy = false;

  /// uids that were successfully resent this session (row shows a tick).
  final Set<String> _sentUids = {};

  List<AdminVerificationTarget> get _missed => AdminVerificationTarget.missedUsers(
        widget.records.map((r) => r.verificationTarget),
      );

  Future<ResendOutcome> _resendOne(String uid) {
    final override = widget.resendOneOverride;
    if (override != null) return override(uid);
    return AdminVerificationResendService.instance.resendOne(uid);
  }

  Future<BulkResendOutcome> _resendBulk(List<String> uids) {
    final override = widget.resendBulkOverride;
    if (override != null) return override(uids);
    return AdminVerificationResendService.instance.resendBulk(uids);
  }

  Future<void> _onResendRow(AdminVerificationTarget target) async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — resending is restricted to platform admins.',
          error: true);
      return;
    }
    if (_busyUids.contains(target.uid)) return;
    setState(() => _busyUids.add(target.uid));
    final outcome = await _resendOne(target.uid);
    if (!mounted) return;
    setState(() {
      _busyUids.remove(target.uid);
      if (outcome.delivered) _sentUids.add(target.uid);
    });
    _showMessage(outcome.message, error: !outcome.delivered);
  }

  Future<void> _onResendBulk() async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — resending is restricted to platform admins.',
          error: true);
      return;
    }
    final missed = _missed;
    if (missed.isEmpty) {
      _showMessage('No unverified accounts to resend to.', error: false);
      return;
    }
    final batch = adminVerificationResendBatch(missed);
    final capped = missed.length > batch.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resend verification emails'),
        content: Text(
          'Resend to ${batch.length} user${batch.length == 1 ? '' : 's'}?'
          '${capped ? '\n\nOnly the first ${batch.length} of '
              '${missed.length} will be sent this run (the batch is capped at '
              '$kAdminVerificationResendBatchLimit to protect the email '
              'quota). Re-run to send the remainder.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const ValueKey('adminV2ConfirmBulkResend'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('RESEND'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkBusy = true);
    final outcome = await _resendBulk(batch.map((t) => t.uid).toList());
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    _showMessage(
      'Resent to ${outcome.delivered} of ${outcome.processed}'
      '${outcome.skipped > 0 ? ' (${outcome.skipped} skipped by the cap)' : ''}.',
      error: outcome.delivered == 0,
    );
  }

  void _showMessage(String message, {required bool error}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final missed = _missed;
    final neverSent = missed.where((t) => !t.lastAttemptFailed).length;
    final failed = missed.where((t) => t.lastAttemptFailed).length;

    return Container(
      key: const ValueKey('adminV2VerificationCard'),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Email Verification (${missed.length} unverified)',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Accounts that have not verified their email. '
            '$neverSent never received a send; $failed had a failed attempt.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('adminV2ResendAllUnverifiedButton'),
            onPressed:
                (widget.isAdmin && !_bulkBusy && missed.isNotEmpty)
                    ? _onResendBulk
                    : null,
            icon: _bulkBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.forward_to_inbox_outlined, size: 18),
            label: Text('Resend to All Unverified (${missed.length})'),
          ),
          const SizedBox(height: 12),
          if (missed.isEmpty)
            Text(
              'Every account has verified its email (or has a send on record).',
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            )
          else
            for (final target in missed.take(50)) _row(theme, target),
          if (missed.length > 50) ...[
            const SizedBox(height: 6),
            Text(
              '… and ${missed.length - 50} more. Use the bulk action to '
              'process them in capped batches.',
              style: TextStyle(color: theme.subtitleColor, fontSize: 11),
            ),
          ],
          if (!widget.isAdmin) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Admin only — sign in as a platform admin to resend '
                    'verification emails.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(ThemeController theme, AdminVerificationTarget target) {
    final busy = _busyUids.contains(target.uid);
    final sent = _sentUids.contains(target.uid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.email.isEmpty ? target.uid : target.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textColor, fontSize: 12),
                ),
                Text(
                  target.statusLabel,
                  style: TextStyle(
                    color: target.lastAttemptFailed
                        ? Colors.red.shade700
                        : theme.subtitleColor,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (sent)
            Icon(Icons.check_circle, size: 18, color: Colors.green.shade700)
          else
            TextButton(
              key: ValueKey('adminV2ResendRow_${target.uid}'),
              onPressed:
                  widget.isAdmin ? () => _onResendRow(target) : null,
              child: const Text('RESEND'),
            ),
        ],
      ),
    );
  }
}
