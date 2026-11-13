import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_operational_metrics.dart';
import '../models/admin_user_metrics.dart' show formatAdminDate;
import '../services/admin_operational_metrics_service.dart';
import '../widgets/admin_v2_common.dart';

/// The package statuses offered by the Packages page filter (plus "All").
const List<String> kAdminPackageStatusFilters = [
  'active',
  'sold_out',
  'draft',
  'archived',
  'deleted',
];

/// The Admin Portal V2 **Packages** page (Task 6, Phase 1 — READ ONLY).
///
/// Lists every `packages/{id}` document with its title, outfitter, PROVINCE
/// (joined from `farms/{farmId}`, never read from the package doc), status,
/// `quantityAvailable` and `createdAt`. Filters: status, province and
/// outfitter.
///
/// This page performs NO writes — Phase 1 is read-only.
class AdminPackagesPage extends StatefulWidget {
  final ThemeController theme;
  final AdminOperationalData data;

  const AdminPackagesPage({
    super.key,
    required this.theme,
    required this.data,
  });

  @override
  State<AdminPackagesPage> createState() => _AdminPackagesPageState();
}

class _AdminPackagesPageState extends State<AdminPackagesPage> {
  /// `null` = All.
  String? _statusFilter;
  String? _provinceFilter;
  String? _outfitterFilter;

  String _outfitterLabel(String uid) {
    final name = widget.data.outfitterNameByUid[uid];
    if (name != null && name.isNotEmpty) return name;
    final email = widget.data.emailByUid[uid];
    if (email != null && email.isNotEmpty) return email;
    return uid;
  }

  List<AdminPackageRecord> get _filtered {
    return widget.data.packages.where((p) {
      if (_statusFilter != null && p.status != _statusFilter) return false;
      if (_provinceFilter != null && p.provinceBucket != _provinceFilter) {
        return false;
      }
      if (_outfitterFilter != null && p.outfitterId != _outfitterFilter) {
        return false;
      }
      return true;
    }).toList(growable: false)
      ..sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return a.title.compareTo(b.title);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
  }

  /// The outfitters that actually own at least one package (for the filter).
  List<String> get _packageOutfitters {
    final ids = <String>{
      for (final p in widget.data.packages)
        if (p.outfitterId.isNotEmpty) p.outfitterId,
    };
    final list = ids.toList()
      ..sort((a, b) => _outfitterLabel(a).compareTo(_outfitterLabel(b)));
    return list;
  }

  List<String> get _provinceOptions {
    final seen = <String>{
      for (final p in widget.data.packages) p.provinceBucket,
    };
    final list = seen.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final outfitters = _packageOutfitters;

    return Column(
      key: const ValueKey('adminV2PackagesPage'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
        ),
        const SizedBox(height: 6),
        AdminV2FilterChipBar<String?>(
          theme: widget.theme,
          keyPrefix: 'adminV2PackageStatus_',
          values: [null, ...kAdminPackageStatusFilters],
          selected: _statusFilter,
          labelOf: (v) => v ?? 'All',
          onSelected: (v) => setState(() => _statusFilter = v),
        ),
        const SizedBox(height: 12),
        Text(
          'Province',
          style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
        ),
        const SizedBox(height: 6),
        AdminV2FilterChipBar<String?>(
          theme: widget.theme,
          keyPrefix: 'adminV2PackageProvince_',
          values: [null, ..._provinceOptions],
          selected: _provinceFilter,
          labelOf: (v) => v ?? 'All',
          onSelected: (v) => setState(() => _provinceFilter = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Outfitter',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  key: const ValueKey('adminV2PackageOutfitterDropdown'),
                  value: _outfitterFilter,
                  isExpanded: true,
                  dropdownColor: widget.theme.cardColor,
                  style: TextStyle(color: widget.theme.textColor, fontSize: 13),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All outfitters',
                        style: TextStyle(color: widget.theme.textColor),
                      ),
                    ),
                    for (final uid in outfitters)
                      DropdownMenuItem<String?>(
                        value: uid,
                        child: Text(
                          _outfitterLabel(uid),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: widget.theme.textColor),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _outfitterFilter = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AdminV2TableCard(
          key: const ValueKey('adminV2PackagesTable'),
          theme: widget.theme,
          title:
              'Packages (${filtered.length} of ${widget.data.packages.length})',
          emptyLabel: 'No packages match the current filters.',
          headers: const [
            'Title',
            'Outfitter',
            'Province',
            'Status',
            'Qty',
            'Created',
          ],
          rows: [
            for (final p in filtered)
              [
                p.title.isEmpty ? '(untitled package)' : p.title,
                p.outfitterId.isEmpty
                    ? '—'
                    : _outfitterLabel(p.outfitterId),
                p.provinceBucket,
                p.status.isEmpty ? '—' : p.status,
                p.quantityAvailable.toString(),
                formatAdminDate(p.createdAt),
              ],
          ],
        ),
        AdminV2Note(
          theme: widget.theme,
          text: 'Read-only (Phase 1). Province is JOINED from farms/{farmId} '
              '— a missing farm lands in "$kUnknownProvince". '
              '${widget.data.packages.length} package'
              '${widget.data.packages.length == 1 ? '' : 's'} loaded.',
        ),
      ],
    );
  }
}
