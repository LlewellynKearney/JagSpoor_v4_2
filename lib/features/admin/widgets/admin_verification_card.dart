import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_user_metrics.dart';
import '../models/admin_verification_target.dart';
import '../services/admin_verification_resend_service.dart';

/// The Admin Portal V2 "Email Verification" card (Users tab).
///
/// Shows the unverified accounts split into the TWO buckets that need different
/// actions — a single "Resend to All Unverified (72)" button would SPAM active
/// users, because role selection in JagSpoor does not require a verified email:
///
///   * **Resend to No Role (N)** — BUCKET 2: unverified AND no role. These
///     accounts never finished signup and likely never got the email. This is
///     the ONLY bulk resend target (capped at
///     [kAdminVerificationResendBatchLimit] per run).
///   * **Remind Unverified With Role (M)** — BUCKET 1: unverified but has a
///     role. Active users who received the email and never clicked. They get a
///     reminder; they are NEVER bulk re-sent. The reminder action opens a
///     pre-filled support-mail draft (mailto with BCC) addressed to those
///     accounts so the admin sends a gentle nudge, not a fresh verification
///     link.
///
/// Per-row **RESEND** stays available on both lists (an explicit, one-off
/// admin decision per account).
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

  /// Test seam: override the reminder mail hand-off (defaults to `url_launcher`
  /// `mailto:`). Returns whether the hand-off succeeded.
  final Future<bool> Function(Uri mailto)? launchReminderOverride;

  const AdminVerificationCard({
    super.key,
    required this.theme,
    required this.records,
    required this.isAdmin,
    this.resendOneOverride,
    this.resendBulkOverride,
    this.launchReminderOverride,
  });

  @override
  State<AdminVerificationCard> createState() => _AdminVerificationCardState();
}

class _AdminVerificationCardState extends State<AdminVerificationCard> {
  /// uid -> in-flight (per-row spinner).
  final Set<String> _busyUids = {};

  /// Whether the no-role bulk resend is in flight.
  bool _bulkBusy = false;

  /// uids that were successfully resent this session (row shows a tick).
  final Set<String> _sentUids = {};

  List<AdminVerificationTarget> get _targets =>
      widget.records.map((r) => r.verificationTarget).toList();

  /// BUCKET 2 — the resend targets.
  List<AdminVerificationTarget> get _noRole =>
      AdminVerificationTarget.noRoleUsers(_targets);

  /// BUCKET 1 — reminder only.
  List<AdminVerificationTarget> get _withRole =>
      AdminVerificationTarget.withRoleUsers(_targets);

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

  Future<bool> _launchReminder(Uri mailto) {
    final override = widget.launchReminderOverride;
    if (override != null) return override(mailto);
    return AdminVerificationResendService.instance.launchMailto(mailto);
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

  Future<void> _onResendNoRole() async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — resending is restricted to platform admins.',
          error: true);
      return;
    }
    final noRole = _noRole;
    if (noRole.isEmpty) {
      _showMessage('No no-role accounts to resend to.', error: false);
      return;
    }
    final batch = adminVerificationResendBatch(noRole);
    final capped = noRole.length > batch.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resend verification emails'),
        content: Text(
          'Resend to ${batch.length} no-role user'
          '${batch.length == 1 ? '' : 's'}?'
          '${capped ? '\n\nOnly the first ${batch.length} of '
              '${noRole.length} will be sent this run (the batch is capped at '
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
    if (outcome.delivered == 0) {
      // Nothing was delivered. When the server rejected the run with a
      // credential/IAM `failed-precondition`, `outcome.message` carries the
      // actionable diagnostic (the exact service account + the missing role).
      // Showing "0 of 0" here is what hid the real problem — surface the
      // diagnostic instead.
      _showMessage(outcome.message, error: true);
      return;
    }
    _showMessage(
      'Resent to ${outcome.delivered} of ${outcome.processed}'
      '${outcome.skipped > 0 ? ' (${outcome.skipped} skipped by the cap)' : ''}.',
      error: false,
    );
  }

  /// Opens a pre-filled support-mail draft (mailto, BCC) so the admin can send
  /// a gentle reminder to the role-bearing unverified accounts WITHOUT minting
  /// fresh verification links (which would spam active users).
  Future<void> _onRemindWithRole() async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — reminders are restricted to platform admins.',
          error: true);
      return;
    }
    final emails = _withRole
        .map((t) => t.email)
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (emails.isEmpty) {
      _showMessage('No role-bearing unverified accounts to remind.',
          error: false);
      return;
    }
    final mailto = Uri(
      scheme: 'mailto',
      path: 'support@jag-spoor.co.za',
      query: _buildReminderQuery(emails),
    );
    final ok = await _launchReminder(mailto);
    if (!mounted) return;
    if (!ok) {
      _showMessage(
        'Could not open your mail app — email ${emails.length} '
        'unverified user${emails.length == 1 ? '' : 's'} manually.',
        error: true,
      );
    }
  }

  /// Builds the mailto query (subject + body + BCC). Pure + testable.
  static String _buildReminderQuery(List<String> emails) {
    const subject = 'Please verify your JagSpoor email address';
    final body = [
      'Hello,',
      '',
      'Our records show your JagSpoor email address is not yet verified.',
      'Verifying keeps your account secure and ensures you receive booking',
      'and licence updates. If you still have the original verification',
      'email, please open it and tap the confirmation link. If you cannot',
      'find it, reply to this message and we will send a fresh link.',
      '',
      'Thank you,',
      'The JagSpoor Team',
    ].join('\n');
    return _encodeQuery({
      'subject': subject,
      'body': body,
      'bcc': emails.join(','),
    });
  }

  /// Percent-encodes a mailto query map (spaces as %20, no `+` artifacts).
  static String _encodeQuery(Map<String, String> params) {
    final parts = <String>[];
    for (final entry in params.entries) {
      if (entry.value.isEmpty) continue;
      parts.add(
        '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      );
    }
    return parts.join('&');
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
    final noRole = _noRole;
    final withRole = _withRole;

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
                  'Email Verification',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Bucket 2: no role → the resend targets ──────────────────────
          Text(
            'No Role (${noRole.length})',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Never completed signup — likely never got the email. '
            'These are the resend targets.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('adminV2ResendNoRoleButton'),
            onPressed:
                (widget.isAdmin && !_bulkBusy && noRole.isNotEmpty)
                    ? _onResendNoRole
                    : null,
            icon: _bulkBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.forward_to_inbox_outlined, size: 18),
            label: Text('Resend to No Role (${noRole.length})'),
          ),
          if (noRole.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No no-role unverified accounts.',
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              ),
            )
          else
            for (final t in noRole.take(50)) _row(theme, t),
          if (noRole.length > 50)
            Text(
              '… and ${noRole.length - 50} more. Use the bulk action to '
              'process them in capped batches.',
              style: TextStyle(color: theme.subtitleColor, fontSize: 11),
            ),
          const SizedBox(height: 16),
          Divider(color: theme.textColor.withAlpha(15)),
          const SizedBox(height: 8),
          // ── Bucket 1: with role → reminder only ─────────────────────────
          Text(
            'Unverified With Role (${withRole.length})',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Unverified but active — received email, never clicked. '
            'Do NOT bulk resend, send a reminder only.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('adminV2RemindWithRoleButton'),
            onPressed: (widget.isAdmin && withRole.isNotEmpty)
                ? _onRemindWithRole
                : null,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text('Remind Unverified With Role (${withRole.length})'),
          ),
          if (withRole.isNotEmpty)
            for (final t in withRole.take(50)) _row(theme, t),
          if (withRole.length > 50)
            Text(
              '… and ${withRole.length - 50} more.',
              style: TextStyle(color: theme.subtitleColor, fontSize: 11),
            ),
          if (!widget.isAdmin) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Admin only — sign in as a platform admin to resend or '
                    'remind.',
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
                  target.hasRole
                      ? '${target.statusLabel} · ${target.role}'
                      : target.statusLabel,
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
