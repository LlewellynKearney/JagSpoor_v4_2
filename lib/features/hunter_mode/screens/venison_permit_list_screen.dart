import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/venison_transport_permit.dart';
import '../services/venison_permit_manager.dart';
import '../services/venison_permit_pdf_exporter.dart';
import '../widgets/venison_permit_details_sheet.dart';
import 'venison_permit_form_screen.dart';

/// Permit log / manager for issued SA venison transport & hunt permits.
///
/// Renders a reactive, searchable list of permits for the authenticated user
/// (outfitters see permits they issued; hunters see permits issued to them).
/// Tap a card to open a details sheet with the full permit breakdown, both
/// captured signatures, and actions to void or delete a permit.
class VenisonPermitListScreen extends StatefulWidget {
  final ThemeController theme;

  /// When true the stream is scoped to the outfitter's issued permits;
  /// otherwise the hunter's permits.
  final bool isOutfitterMode;

  /// Optional booking context — passed through to the "new permit" form so it
  /// can pre-fill from the booking.
  final String? bookingId;

  const VenisonPermitListScreen({
    super.key,
    required this.theme,
    this.isOutfitterMode = true,
    this.bookingId,
  });

  @override
  State<VenisonPermitListScreen> createState() =>
      _VenisonPermitListScreenState();
}

class _VenisonPermitListScreenState extends State<VenisonPermitListScreen> {
  final _permitManager = VenisonPermitManager.instance;
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

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isOutfitterMode ? 'Issued Permits' : 'My Transport Permits',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: theme.accentColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Permit'),
      ),
      body: Column(
        children: [
          _buildSearchBar(theme),
          Expanded(
            child: StreamBuilder<List<VenisonTransportPermit>>(
              stream: _permitManager.getMyPermitsStream(
                isOutfitter: widget.isOutfitterMode,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: theme.accentColor),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorState(theme, snapshot.error.toString());
                }

                final permits = snapshot.data ?? [];
                final filtered = _filterPermits(permits);

                if (filtered.isEmpty) {
                  return _buildEmptyState(theme);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _PermitCard(
                    permit: filtered[index],
                    theme: theme,
                    onTap: () => _showDetails(filtered[index]),
                    onVoid: () => _voidPermit(filtered[index]),
                    onDelete: () => _confirmDelete(filtered[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeController theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: TextStyle(color: theme.textColor),
        decoration: InputDecoration(
          hintText: 'Search by hunter, farm, species, or permit no.',
          hintStyle: TextStyle(color: theme.subtitleColor),
          prefixIcon: Icon(Icons.search_rounded, color: theme.subtitleColor),
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
          fillColor: theme.cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
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
        p.hunterName,
        p.farmName,
        p.authorizedPersonName,
        p.permitNumber,
        p.speciesSummary,
        p.status,
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  Widget _buildEmptyState(ThemeController theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64,
                color: theme.subtitleColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No Permits Yet',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Issued SA venison transport & hunt permits will appear here. '
              'Tap "New Permit" to create one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeController theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('Could not load permits',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'If this persists, the required Firestore composite index '
              '(venison_permits: outfitterId/hunterId ASC + createdAt DESC) '
              'may still be building.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _openForm() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VenisonPermitFormScreen(
          theme: widget.theme,
          isOutfitterMode: widget.isOutfitterMode,
          bookingId: widget.bookingId,
        ),
      ),
    );
  }

  void _showDetails(VenisonTransportPermit permit) {
    VenisonPermitDetailsSheet.show(
      context,
      permit: permit,
      theme: widget.theme,
      onExport: () => _exportPermit(permit),
      onVoid: () => _voidPermit(permit),
      onDelete: () => _confirmDelete(permit),
    );
  }

  Future<void> _exportPermit(VenisonTransportPermit permit) async {
    if (permit.id == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating permit PDF…')),
    );
    try {
      await exportVenisonPermitPdf(permit.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permit PDF exported and shared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _voidPermit(VenisonTransportPermit permit) async {
    try {
      await _permitManager.updatePermitStatus(
        permitId: permit.id!,
        newStatus: 'Voided',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permit voided'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(VenisonTransportPermit permit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text('Delete Permit?',
            style: TextStyle(color: widget.theme.textColor)),
        content: Text(
          'This permanently deletes the permit and its stored signatures. '
          'This cannot be undone.',
          style: TextStyle(color: widget.theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _permitManager.deletePermit(permit.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permit deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

/// A single permit list card.
class _PermitCard extends StatelessWidget {
  final VenisonTransportPermit permit;
  final ThemeController theme;
  final VoidCallback onTap;
  final VoidCallback onVoid;
  final VoidCallback onDelete;

  const _PermitCard({
    required this.permit,
    required this.theme,
    required this.onTap,
    required this.onVoid,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(permit.status);

    return Card(
      color: theme.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          permit.hunterName.isEmpty
                              ? 'Unknown hunter'
                              : permit.hunterName,
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          permit.farmName.isEmpty
                              ? 'Unknown farm'
                              : permit.farmName,
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pets_rounded,
                        color: theme.accentColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        permit.speciesSummary,
                        style:
                            TextStyle(color: theme.textColor, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.event_rounded,
                      color: theme.subtitleColor, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _huntWindow,
                      style:
                          TextStyle(color: theme.subtitleColor, fontSize: 11),
                    ),
                  ),
                  Icon(Icons.draw_rounded,
                      color: permit.isFullySigned
                          ? Colors.green
                          : Colors.amber.shade700,
                      size: 16),
                  const SizedBox(width: 4),
                  Text(
                    permit.isFullySigned ? 'Signed' : 'Pending sig.',
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
            ],
          ),
        ),
      ),
    );
  }

  String get _huntWindow {
    return '${_fmtDate(permit.huntStartDate)} → ${_fmtDate(permit.huntEndDate)}';
  }

  String _fmtDate(DateTime? d) =>
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
}
