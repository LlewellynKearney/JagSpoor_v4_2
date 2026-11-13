import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../hunter_mode/models/booking_status.dart';
import '../models/admin_operational_metrics.dart';
import '../models/admin_user_metrics.dart' show formatAdminDate;
import '../services/admin_operational_metrics_service.dart';
import '../widgets/admin_v2_common.dart';

/// The Admin Portal V2 **Bookings** page (Task 6, Phase 1 — READ ONLY).
///
/// Lists every `bookings/{id}` document with the hunter email, outfitter email,
/// package title, status, `createdAt` and — for bookings stuck in
/// Pending Approval for more than 7 days — the days stuck. The days-to-confirm
/// metric uses `paymentVerifiedAt` (NOT `confirmedAt`, which does not exist on
/// real bookings).
///
/// This page performs NO writes — Phase 1 is read-only.
class AdminBookingsPage extends StatefulWidget {
  final ThemeController theme;
  final AdminOperationalData data;

  const AdminBookingsPage({
    super.key,
    required this.theme,
    required this.data,
  });

  @override
  State<AdminBookingsPage> createState() => _AdminBookingsPageState();
}

class _AdminBookingsPageState extends State<AdminBookingsPage> {
  /// `null` = All statuses.
  String? _statusFilter;

  String _email(String uid) {
    if (uid.isEmpty) return '—';
    final email = widget.data.emailByUid[uid];
    return (email == null || email.isEmpty) ? uid : email;
  }

  String _packageTitle(AdminBookingRecord b) {
    if (b.packageName.isNotEmpty) return b.packageName;
    final title = widget.data.packageTitleById[b.packageId];
    if (title != null && title.isNotEmpty) return title;
    return b.packageId.isEmpty ? '—' : b.packageId;
  }

  List<AdminBookingRecord> get _filtered {
    return widget.data.bookings.where((b) {
      if (_statusFilter != null && b.normalizedStatus != _statusFilter) {
        return false;
      }
      return true;
    }).toList(growable: false)
      ..sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return a.id.compareTo(b.id);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered = _filtered;

    return Column(
      key: const ValueKey('adminV2BookingsPage'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
        ),
        const SizedBox(height: 6),
        AdminV2FilterChipBar<String?>(
          theme: widget.theme,
          keyPrefix: 'adminV2BookingStatus_',
          values: [null, ...BookingStatus.allStatuses],
          selected: _statusFilter,
          labelOf: (v) => v ?? 'All',
          onSelected: (v) => setState(() => _statusFilter = v),
        ),
        const SizedBox(height: 12),
        AdminV2TableCard(
          key: const ValueKey('adminV2BookingsTable'),
          theme: widget.theme,
          title:
              'Bookings (${filtered.length} of ${widget.data.bookings.length})',
          emptyLabel: 'No bookings match the current filter.',
          headers: const [
            'Hunter',
            'Outfitter',
            'Package',
            'Status',
            'Created',
            'Days Stuck',
          ],
          rows: [
            for (final b in filtered)
              [
                _email(b.hunterId),
                _email(b.outfitterId),
                _packageTitle(b),
                b.normalizedStatus.isEmpty ? '—' : b.normalizedStatus,
                formatAdminDate(b.createdAt),
                b.isStuckPending(now) && b.createdAt != null
                    ? now.difference(b.createdAt!).inDays.toString()
                    : '—',
              ],
          ],
        ),
        AdminV2Note(
          theme: widget.theme,
          text: 'Read-only (Phase 1). Days Stuck shows only for Pending '
              'Approval older than 7 days. Payment timing uses '
              'paymentVerifiedAt (never confirmedAt). Booking payment is '
              'off-platform (EFT / cash), so no booking amount is shown as '
              'revenue.',
        ),
      ],
    );
  }
}
