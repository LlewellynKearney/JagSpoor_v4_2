import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/venison_transport_permit.dart';
import '../services/venison_permit_manager.dart';
import '../services/venison_permit_pdf_exporter.dart';
import '../widgets/venison_permit_details_sheet.dart';
import '../widgets/hunter_scaffold.dart';
import 'venison_permit_form_screen.dart';

/// Dedicated hunter-facing log of issued SA venison / game transport & hunt
/// permits.
///
/// Renders a reactive, searchable list of the permits issued to the signed-in
/// hunter. Each card surfaces the structured statutory details (permit number,
/// issuing outfitter/farm, game species/carcass info, date issued, validity
/// window, signature status) and offers quick actions to VIEW the full permit,
/// or RE-DOWNLOAD/SHARE the official permit PDF directly from the log.
class HunterVenisonPermitLogScreen extends StatefulWidget {
  final ThemeController theme;

  /// Optional booking context forwarded to the "new permit" form.
  final String? bookingId;

  const HunterVenisonPermitLogScreen({
    super.key,
    required this.theme,
    this.bookingId,
  });

  @override
  State<HunterVenisonPermitLogScreen> createState() =>
      _HunterVenisonPermitLogScreenState();
}

class _HunterVenisonPermitLogScreenState
    extends State<HunterVenisonPermitLogScreen> {
  final VenisonPermitManager _permitManager = VenisonPermitManager.instance;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return HunterScaffold(
      theme: theme,
      appBar: AppBar(
        title: Text(
          'MY VENISON PERMITS',
          style: TextStyle(
            color: HunterUi.titleColor(theme),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VenisonPermitFormScreen(
              theme: theme,
              isOutfitterMode: false,
              bookingId: widget.bookingId,
            ),
          ),
        ),
        backgroundColor: theme.accentColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Permit'),
      ),
      body: SafeArea(
        top: true,
        child: Column(
          children: [
            _buildSearchBar(theme),
          Expanded(
            child: StreamBuilder<List<VenisonTransportPermit>>(
              stream: _permitManager.getMyPermitsStream(isOutfitter: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: theme.accentColor),
                  );
                }
                if (snapshot.hasError) {
                  return _buildStateMessage(
                    theme,
                    icon: Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    title: 'Could not load permits',
                    message:
                        'Permits require a Firestore index or sign-in. '
                        '${snapshot.error}',
                  );
                }
                final permits = snapshot.data ?? [];
                final filtered = _filterPermits(permits);
                if (filtered.isEmpty) {
                  return _buildStateMessage(
                    theme,
                    icon: Icons.receipt_long_outlined,
                    color: theme.accentColor,
                    title: _query.isEmpty
                        ? 'No permits issued yet'
                        : 'No permits match "$_query"',
                    message: _query.isEmpty
                        ? 'Permits issued to you by an outfitter will appear '
                          'here. Tap NEW PERMIT to co-complete a permit, then '
                          're-download or share its PDF anytime.'
                        : 'Try a different search term.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _HunterPermitCard(
                    permit: filtered[i],
                    theme: theme,
                    onView: () => VenisonPermitDetailsSheet.show(
                      context,
                      permit: filtered[i],
                      theme: theme,
                      onExport: () => _exportPermit(filtered[i]),
                    ),
                    onDownloadPdf: () => _exportPermit(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeController theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: TextStyle(color: HunterUi.titleColor(theme)),
        decoration: InputDecoration(
          hintText: 'Search permit no., farm, outfitter, or species',
          hintStyle: TextStyle(color: HunterUi.subtitleColor(theme)),
          prefixIcon: Icon(Icons.search_rounded, color: HunterUi.subtitleColor(theme)),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          filled: true,
          fillColor: HunterUi.cardColor(theme),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.accentColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  List<VenisonTransportPermit> _filterPermits(
      List<VenisonTransportPermit> permits) {
    if (_query.isEmpty) return permits;
    return permits.where((p) {
      final hay = [
        p.permitNumber,
        p.hunterName,
        p.farmName,
        p.authorizedPersonName,
        p.speciesSummary,
        p.status,
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  Future<void> _exportPermit(VenisonTransportPermit permit) async {
    if (permit.id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generating permit PDF…')),
    );
    try {
      await exportVenisonPermitPdf(permit.id!);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Permit PDF exported and shared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStateMessage(
    ThemeController theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A structured permit card for the hunter log: surfaces the statutory
/// summary (permit no., issuing outfitter/farm, species/carcass, date issued,
/// validity window, status, signature state) with inline VIEW + DOWNLOAD/SHARE
/// PDF quick actions.
class _HunterPermitCard extends StatelessWidget {
  final VenisonTransportPermit permit;
  final ThemeController theme;
  final VoidCallback onView;
  final VoidCallback onDownloadPdf;

  const _HunterPermitCard({
    required this.permit,
    required this.theme,
    required this.onView,
    required this.onDownloadPdf,
  });

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'issued':
        return Colors.green;
      case 'voided':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(permit.status);

    return Card(
      color: HunterUi.cardColor(theme),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: permit no. + status.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_rounded,
                        color: theme.accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          permit.permitNumber.isEmpty
                              ? 'Permit'
                              : permit.permitNumber,
                          style: TextStyle(
                            color: HunterUi.titleColor(theme),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          permit.isFullySigned ? 'Fully signed' : 'Pending signatures',
                          style: TextStyle(
                            color: permit.isFullySigned
                                ? Colors.green
                                : Colors.amber.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      permit.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Structured detail grid.
              _DetailGrid(theme: theme, rows: [
                _DetailGridRow(
                  icon: Icons.agriculture_rounded,
                  label: 'Issuing farm',
                  value: permit.farmName.isEmpty
                      ? '—'
                      : permit.farmName,
                ),
                _DetailGridRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Authorized by',
                  value: permit.authorizedPersonName.isEmpty
                      ? '—'
                      : permit.authorizedPersonName,
                ),
                _DetailGridRow(
                  icon: Icons.pets_rounded,
                  label: 'Game / carcass',
                  value: permit.speciesSummary,
                  multiline: true,
                ),
                _DetailGridRow(
                  icon: Icons.event_available_rounded,
                  label: 'Date issued',
                  value: _fmt(permit.createdAt),
                ),
                _DetailGridRow(
                  icon: Icons.date_range_rounded,
                  label: 'Valid',
                  value:
                      '${_fmt(permit.huntStartDate)} → ${_fmt(permit.huntEndDate)}',
                  multiline: true,
                ),
              ]),
              const SizedBox(height: 12),
              // Inline quick actions: VIEW + DOWNLOAD/SHARE PDF.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onView,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.accentColor,
                        side: BorderSide(color: theme.accentColor, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('VIEW',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onDownloadPdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  final ThemeController theme;
  final List<_DetailGridRow> rows;

  const _DetailGrid({required this.theme, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: rows
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.icon, color: HunterUi.subtitleColor(theme), size: 16),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: Text(
                          r.label,
                          style: TextStyle(
                            color: HunterUi.subtitleColor(theme),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.value.isEmpty ? '—' : r.value,
                          style: TextStyle(
                            color: HunterUi.titleColor(theme),
                            fontSize: 12,
                          ),
                          maxLines: r.multiline ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _DetailGridRow {
  final IconData icon;
  final String label;
  final String value;
  final bool multiline;

  const _DetailGridRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });
}
