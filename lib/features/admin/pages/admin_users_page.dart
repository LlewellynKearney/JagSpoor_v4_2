import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_user_metrics.dart';
import '../widgets/admin_users_export_card.dart';
import '../widgets/admin_v2_common.dart';

/// The Admin Portal V2 **Users** page (Task 6, Phase 1 — READ ONLY).
///
/// Lists every fetched `users/{uid}` document with its email, role, trial
/// state, `subscriptionProduct`, `subscriptionProvider` and `createdAt`.
/// Supports a free-text email search and a role filter (Hunter / Outfitter /
/// Dual / No Role). A dedicated "No Role" section surfaces accounts that have
/// no operational role at all.
///
/// This page performs NO writes — Phase 1 is read-only.
class AdminUsersPage extends StatefulWidget {
  final ThemeController theme;
  final List<AdminUserRecord> records;

  /// Whether the current user is a platform admin. The CSV export buttons are
  /// gated on this — a non-admin sees the card disabled with an "Admin only"
  /// note and the emails are never exposed.
  final bool isAdmin;

  /// Whether this page renders its own "Users Export (CSV)" card.
  ///
  /// Defaults to `true` so the page is self-contained when used directly. The
  /// Admin Portal V2 Users tab renders the card itself (so the card is owned by
  /// the V2 screen, exactly as the brief specifies) and passes `false` here to
  /// avoid rendering two cards.
  final bool showExportCard;

  const AdminUsersPage({
    super.key,
    required this.theme,
    required this.records,
    this.isAdmin = false,
    this.showExportCard = true,
  });

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final TextEditingController _search = TextEditingController();

  /// `null` = All roles.
  AdminUserRoleCategory? _roleFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminUserRecord> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return widget.records.where((r) {
      if (_roleFilter != null && r.roleCategory != _roleFilter) return false;
      if (query.isNotEmpty && !r.email.contains(query)) return false;
      return true;
    }).toList(growable: false)
      ..sort((a, b) {
        // Newest accounts first; undated documents sort last.
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return a.email.compareTo(b.email);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
  }

  List<AdminUserRecord> get _noRole =>
      widget.records.where((r) => r.hasNoOperationalRole).toList(growable: false)
        ..sort((a, b) => a.email.compareTo(b.email));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered = _filtered;
    final noRole = _noRole;

    return Column(
      key: const ValueKey('adminV2UsersPage'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showExportCard) ...[
          AdminUsersExportCard(
            theme: widget.theme,
            records: widget.records,
            isAdmin: widget.isAdmin,
          ),
          const SizedBox(height: 12),
        ],
        AdminV2SearchField(
          theme: widget.theme,
          controller: _search,
          hint: 'Search by email…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AdminV2FilterChipBar<AdminUserRoleCategory?>(
          theme: widget.theme,
          keyPrefix: 'adminV2UserRole_',
          keyOf: (v) => v?.name ?? 'all',
          values: [null, ...AdminUserRoleCategory.values],
          selected: _roleFilter,
          labelOf: (v) => v == null ? 'All' : v.label,
          onSelected: (v) => setState(() => _roleFilter = v),
        ),
        const SizedBox(height: 12),
        AdminV2TableCard(
          key: const ValueKey('adminV2UsersTable'),
          theme: widget.theme,
          title: 'Users (${filtered.length} of ${widget.records.length})',
          emptyLabel: 'No users match the current search / role filter.',
          headers: const [
            'Email',
            'Name',
            'Surname',
            'Role',
            'Trial',
            'Start',
            'End',
            'Plan',
            'Provider',
          ],
          rows: [
            for (final r in filtered)
              [
                r.email.isEmpty ? '—' : r.email,
                r.firstName.isEmpty ? '—' : r.firstName,
                r.lastName.isEmpty ? '—' : r.lastName,
                _roleLabel(r),
                r.trialLabel(now),
                formatAdminDate(r.trialStart),
                formatAdminDate(r.trialEnd),
                r.plan.isEmpty ? '—' : r.plan,
                r.provider.isEmpty ? '—' : r.provider,
              ],
          ],
          // The two date columns (5 = Start, 6 = End) get a HARD 115 px so a
          // full `YYYY-MM-DD` value is never clipped. FixedColumnWidth is
          // honoured identically by the Web and native renderers, unlike
          // IntrinsicColumnWidth (unreliable in the browser). The wider table
          // keeps the flex columns from shrinking; the whole table still
          // scrolls horizontally on a narrow phone.
          fixedColumnWidths: const {5: 115, 6: 115},
          minTableWidth: 760,
          // Color-code the Trial cell (col 4) green for Active / Converted and
          // red for Expired, plus a subtle matching row tint.
          cellColors: [
            for (final r in filtered) _userRowCellColors(r, now),
          ],
          rowTints: [
            for (final r in filtered)
              trialRowTint(r.trialLabel(now),
                  isDarkMode: widget.theme.isDarkMode),
          ],
        ),
        const SizedBox(height: 16),
        AdminV2SectionHeader(
            theme: widget.theme, title: 'No Role (${noRole.length})'),
        AdminV2TableCard(
          key: const ValueKey('adminV2NoRoleTable'),
          theme: widget.theme,
          title: 'Accounts With No Operational Role',
          emptyLabel: 'Every account has a role assigned.',
          headers: const ['Email', 'Stored Role'],
          rows: [
            for (final r in noRole)
              [
                r.email.isEmpty ? '—' : r.email,
                r.role.isEmpty ? '(none)' : r.role,
              ],
          ],
        ),
        AdminV2Note(
          theme: widget.theme,
          text: 'Read-only (Phase 1). Trial is COMPUTED as of now (Active / '
              'Expired / Converted / None) and color-coded: green = Active / '
              'Converted, red = Expired. Trial dates are YYYY-MM-DD. '
              'Plan = subscriptionProduct, Provider = subscriptionProvider. '
              'No Role = not hunter / outfitter / dual (admins included).',
        ),
      ],
    );
  }

  String _roleLabel(AdminUserRecord r) {
    switch (r.roleCategory) {
      case AdminUserRoleCategory.hunter:
        return 'Hunter';
      case AdminUserRoleCategory.outfitter:
        return 'Outfitter';
      case AdminUserRoleCategory.dual:
        return 'Dual';
      case AdminUserRoleCategory.noRole:
        return 'No Role';
    }
  }

  /// Per-cell color overrides for one Users-table row. Only the **Trial** cell
  /// (index 4) is color-coded; every other cell keeps the default theme text
  /// color (`null`).
  List<Color?> _userRowCellColors(AdminUserRecord r, DateTime now) {
    final colors = List<Color?>.filled(9, null);
    colors[4] = trialStatusColor(
      r.trialLabel(now),
      isDarkMode: widget.theme.isDarkMode,
    );
    return colors;
  }
}
