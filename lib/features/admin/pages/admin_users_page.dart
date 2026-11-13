import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_user_metrics.dart';
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

  const AdminUsersPage({
    super.key,
    required this.theme,
    required this.records,
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
            'Role',
            'Trial',
            'Plan',
            'Provider',
            'Created',
          ],
          rows: [
            for (final r in filtered)
              [
                r.email.isEmpty ? '—' : r.email,
                _roleLabel(r),
                r.trialLabel(now),
                r.plan.isEmpty ? '—' : r.plan,
                r.provider.isEmpty ? '—' : r.provider,
                formatAdminDate(r.createdAt),
              ],
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
          headers: const ['Email', 'Stored Role', 'Created'],
          rows: [
            for (final r in noRole)
              [
                r.email.isEmpty ? '—' : r.email,
                r.role.isEmpty ? '(none)' : r.role,
                formatAdminDate(r.createdAt),
              ],
          ],
        ),
        AdminV2Note(
          theme: widget.theme,
          text: 'Read-only (Phase 1). Trial is COMPUTED as of now (Active / '
              'Expired / Converted / None). Plan = subscriptionProduct, '
              'Provider = subscriptionProvider. No Role = not hunter / '
              'outfitter / dual (admins included).',
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
}
