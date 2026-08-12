import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../models/venison_transport_permit.dart';
import '../services/venison_permit_manager.dart';
import '../services/venison_permit_pdf_exporter.dart';
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PermitDetailsSheet(
        permit: permit,
        theme: widget.theme,
        onExport: () => _exportPermit(permit),
        onVoid: () {
          Navigator.pop(context);
          _voidPermit(permit);
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(permit);
        },
      ),
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

/// Draggable details sheet showing the full permit breakdown + signatures.
class _PermitDetailsSheet extends StatelessWidget {
  final VenisonTransportPermit permit;
  final ThemeController theme;
  final VoidCallback onExport;
  final VoidCallback onVoid;
  final VoidCallback onDelete;

  const _PermitDetailsSheet({
    required this.permit,
    required this.theme,
    required this.onExport,
    required this.onVoid,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        color: theme.backgroundColor,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.subtitleColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded,
                      color: theme.accentColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Venison Transport Permit',
                            style: TextStyle(
                                color: theme.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(permit.permitNumber,
                            style: TextStyle(
                                color: theme.subtitleColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: theme.subtitleColor,
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _Section(title: 'HUNTER DETAILS', theme: theme, children: [
                    _DetailRow('Name', permit.hunterName, theme),
                    _DetailRow('ID / Passport', permit.hunterIdNumber, theme),
                    _DetailRow('Cell', permit.hunterCell, theme),
                    _DetailRow('Address', permit.hunterAddress, theme),
                  ]),
                  const SizedBox(height: 16),
                  _Section(
                      title: 'AUTHORIZED PERSON / FARM', theme: theme, children: [
                    _DetailRow(
                        'Authorized Person', permit.authorizedPersonName, theme),
                    _DetailRow('Farm', permit.farmName, theme),
                    _DetailRow('Farm Address', permit.farmAddress, theme),
                    _DetailRow('Farm Cell', permit.farmCell, theme),
                  ]),
                  const SizedBox(height: 16),
                  _Section(title: 'HUNT WINDOW', theme: theme, children: [
                    _DetailRow('Start',
                        _fmt(permit.huntStartDate), theme),
                    _DetailRow('End', _fmt(permit.huntEndDate), theme),
                  ]),
                  const SizedBox(height: 16),
                  _Section(
                      title: 'SPECIES HUNTED AND TRANSPORTED',
                      theme: theme,
                      children: permit.speciesHuntedAndTransported.isEmpty
                          ? [_DetailRow('—', 'No species declared', theme)]
                          : permit.speciesHuntedAndTransported
                              .map((s) => _DetailRow(
                                    s['species']?.toString() ?? 'Unknown',
                                    '${s['quantity']}x ${s['sex'] ?? ''}',
                                    theme,
                                  ))
                              .toList()),
                  const SizedBox(height: 16),
                  if (permit.hunterSignatureUrl != null ||
                      permit.outfitterSignatureUrl != null) ...[
                    Text('SIGNATURES',
                        style: TextStyle(
                            color: theme.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (permit.hunterSignatureUrl != null)
                          Expanded(
                            child: _SignatureTile(
                              label: 'Hunter',
                              url: permit.hunterSignatureUrl!,
                              signedDate: permit.hunterSignedDate,
                              theme: theme,
                            ),
                          ),
                        if (permit.hunterSignatureUrl != null &&
                            permit.outfitterSignatureUrl != null)
                          const SizedBox(width: 12),
                        if (permit.outfitterSignatureUrl != null)
                          Expanded(
                            child: _SignatureTile(
                              label: 'Outfitter',
                              url: permit.outfitterSignatureUrl!,
                              signedDate: permit.outfitterSignedDate,
                              theme: theme,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _DetailRow('Status', permit.status, theme),
                  const SizedBox(height: 24),
                  // Export permit PDF
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onExport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('EXPORT PERMIT PDF',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (permit.status != 'Voided')
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onVoid,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.block_rounded, size: 18),
                            label: const Text('VOID',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onDelete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('DELETE',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${d.day}/${d.month}/${d.year}';
}

class _Section extends StatelessWidget {
  final String title;
  final ThemeController theme;
  final List<Widget> children;

  const _Section(
      {required this.title, required this.theme, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: theme.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: theme.accentColor.withValues(alpha: 0.15)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;

  const _DetailRow(this.label, this.value, this.theme);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: theme.textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureTile extends StatelessWidget {
  final String label;
  final String url;
  final DateTime? signedDate;
  final ThemeController theme;

  const _SignatureTile({
    required this.label,
    required this.url,
    required this.signedDate,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label Signature',
            style: TextStyle(
                color: theme.subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          height: 80,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.accentColor),
                ),
              ),
              errorWidget: (_, __, ___) => Icon(Icons.draw_rounded,
                  color: theme.subtitleColor),
            ),
          ),
        ),
        if (signedDate != null) ...[
          const SizedBox(height: 4),
          Text(
            'Signed: ${signedDate!.day}/${signedDate!.month}/${signedDate!.year}',
            style: TextStyle(color: theme.subtitleColor, fontSize: 10),
          ),
        ],
      ],
    );
  }
}
