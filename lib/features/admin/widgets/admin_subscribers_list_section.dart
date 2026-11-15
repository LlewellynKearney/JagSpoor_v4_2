import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_subscription_metrics.dart';
import 'admin_v2_common.dart';

/// The Admin Portal V2 **Subscribers List** section (read-only).
///
/// A searchable + filterable table of the subscription population: Name,
/// Email, Provider (Google / PayFast badge), Plan, Start Date and Status.
/// Sorted by Start Date (newest first) by default — the order
/// [AdminSubscriptionMetrics.aggregate] produces. NO cancel / refund /
/// change-plan affordance exists here.
class AdminSubscribersListSection extends StatefulWidget {
  final ThemeController theme;
  final AdminSubscriptionMetrics metrics;

  const AdminSubscribersListSection({
    super.key,
    required this.theme,
    required this.metrics,
  });

  @override
  State<AdminSubscribersListSection> createState() =>
      _AdminSubscribersListSectionState();
}

class _AdminSubscribersListSectionState
    extends State<AdminSubscribersListSection> {
  final TextEditingController _search = TextEditingController();
  AdminSubscriberFilter _filter = AdminSubscriberFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final rows = widget.metrics.visibleSubscribers(
      query: _search.text,
      filter: _filter,
    );

    return Column(
      key: const ValueKey('adminV2SubscribersSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminV2SectionHeader(theme: theme, title: 'Subscribers List'),
        AdminV2SearchField(
          theme: theme,
          controller: _search,
          hint: 'Search by name or email…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AdminV2FilterChipBar<AdminSubscriberFilter>(
          theme: theme,
          keyPrefix: 'adminV2SubscriberFilter_',
          keyOf: (v) => v.name,
          values: AdminSubscriberFilter.values,
          selected: _filter,
          labelOf: (v) => v.label,
          onSelected: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 12),
        Text(
          'Showing ${rows.length} subscriber'
          '${rows.length == 1 ? '' : 's'}',
          key: const ValueKey('adminV2SubscribersCount'),
          style: TextStyle(
            color: theme.subtitleColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildTable(theme, rows),
        AdminV2Note(
          theme: theme,
          text: 'Read-only snapshot "as of now". Provider is read from the '
              'stored subscription fields (Google Play Billing or PayFast, '
              'including alternative / User Choice billing). Sorted by Start '
              'Date (newest first).',
        ),
      ],
    );
  }

  Widget _buildTable(ThemeController theme, List<AdminSubscriberRow> rows) {
    return Container(
      key: const ValueKey('adminV2SubscribersTable'),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(16),
      child: rows.isEmpty
          ? Text(
              'No subscribers match the current search / filter.',
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 640),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2.4),
                    2: FlexColumnWidth(1.3),
                    3: FlexColumnWidth(1.6),
                    4: FlexColumnWidth(1.2),
                    5: FlexColumnWidth(1.1),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: theme.textColor.withAlpha(12),
                    ),
                  ),
                  children: [
                    TableRow(
                      children: [
                        for (final h in const [
                          'Name',
                          'Email',
                          'Provider',
                          'Plan',
                          'Start Date',
                          'Status',
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              h,
                              style: TextStyle(
                                color: theme.accentColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final r in rows)
                      TableRow(
                        children: [
                          _cell(theme, r.name.isEmpty ? '—' : r.name),
                          _cell(theme, r.email.isEmpty ? '—' : r.email),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _providerBadge(theme, r.provider),
                          ),
                          _cell(theme, r.planLabel),
                          _cell(theme, r.startDateLabel),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _statusBadge(theme, r.status),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _cell(ThemeController theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.textColor, fontSize: 12),
        ),
      );

  Widget _providerBadge(ThemeController theme, AdminSubscriptionProvider provider) {
    final isGoogle = provider == AdminSubscriptionProvider.google;
    final isPayfast = provider == AdminSubscriptionProvider.payfast;
    final color = isGoogle
        ? Colors.blue.shade600
        : isPayfast
            ? Colors.green.shade700
            : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        provider.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statusBadge(ThemeController theme, AdminSubscriberStatus status) {
    final color = switch (status) {
      AdminSubscriberStatus.active => Colors.green.shade700,
      AdminSubscriberStatus.trial => Colors.orange.shade800,
      AdminSubscriberStatus.cancelled => Colors.red.shade700,
      AdminSubscriberStatus.expired => theme.subtitleColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
