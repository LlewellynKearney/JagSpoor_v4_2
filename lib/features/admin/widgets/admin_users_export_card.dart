import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_user_metrics.dart';
import '../models/admin_users_csv.dart';
import '../services/csv_export.dart';

/// The Admin Portal V2 "Users Export" card.
///
/// Two admin-only CSV exports of the fetched `users` documents:
///  * **Export All Users (N)** — every user visible to the admin;
///  * **Export Users With No Role (M)** — only accounts with no role, for
///    emailing users stuck without a role.
///
/// The count rendered in each label is [AdminUsersCsv.rowCount] over the same
/// list the CSV is built from, so the label and the file always agree. A
/// non-admin sees the card disabled with an "Admin only" note — the emails are
/// never exposed.
class AdminUsersExportCard extends StatefulWidget {
  final ThemeController theme;
  final List<AdminUserRecord> records;
  final bool isAdmin;

  /// Test seam: overrides the CSV hand-off so a widget test never touches the
  /// browser / share sheet. Returns whether the delivery succeeded.
  final Future<bool> Function({required String fileName, required String content})?
      deliverOverride;

  const AdminUsersExportCard({
    super.key,
    required this.theme,
    required this.records,
    required this.isAdmin,
    this.deliverOverride,
  });

  @override
  State<AdminUsersExportCard> createState() => _AdminUsersExportCardState();
}

class _AdminUsersExportCardState extends State<AdminUsersExportCard> {
  /// Which export is currently in flight (`all` / `noRole`), or null.
  String? _busy;

  Future<bool> _deliver({required String fileName, required String content}) {
    final override = widget.deliverOverride;
    if (override != null) return override(fileName: fileName, content: content);
    return deliverCsv(fileName: fileName, content: content);
  }

  Future<void> _exportAll() async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — CSV export is restricted to platform admins.',
          error: true);
      return;
    }
    setState(() => _busy = 'all');
    final content = AdminUsersCsv.build(widget.records);
    final ok = await _deliver(
      fileName: AdminUsersCsv.allUsersFileName(),
      content: content,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    _showMessage(
      ok
          ? 'Exported ${widget.records.length} user'
              '${widget.records.length == 1 ? '' : 's'} to CSV.'
          : 'Could not export the users CSV.',
      error: !ok,
    );
  }

  Future<void> _exportNoRole() async {
    if (!widget.isAdmin) {
      _showMessage('Admin only — CSV export is restricted to platform admins.',
          error: true);
      return;
    }
    final noRole = AdminUsersCsv.noRoleUsers(widget.records);
    setState(() => _busy = 'noRole');
    final content = AdminUsersCsv.build(noRole);
    final ok = await _deliver(
      fileName: AdminUsersCsv.noRoleFileName(),
      content: content,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    _showMessage(
      ok
          ? 'Exported ${noRole.length} user'
              '${noRole.length == 1 ? '' : 's'} with no role to CSV.'
          : 'Could not export the no-role users CSV.',
      error: !ok,
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
    final allCount = AdminUsersCsv.rowCount(widget.records);
    final noRoleCount = AdminUsersCsv.noRoleUsers(widget.records).length;

    return Container(
      key: const ValueKey('adminV2UsersExportCard'),
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
              Icon(Icons.download_for_offline_outlined,
                  color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Users Export (CSV)',
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
            'Download the user list as a CSV (Web: browser download · '
            'Android: share / save).',
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('adminV2ExportAllUsersButton'),
                onPressed: _busy == null ? _exportAll : null,
                icon: _busy == 'all'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.people_alt_outlined, size: 18),
                label: Text('Export All Users ($allCount)'),
              ),
              FilledButton.icon(
                key: const ValueKey('adminV2ExportNoRoleUsersButton'),
                onPressed: _busy == null ? _exportNoRole : null,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.white,
                ),
                icon: _busy == 'noRole'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_outlined, size: 18),
                label: Text('Export No Role ($noRoleCount)'),
              ),
            ],
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
                    'Admin only — sign in as a platform admin to export users.',
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
}
