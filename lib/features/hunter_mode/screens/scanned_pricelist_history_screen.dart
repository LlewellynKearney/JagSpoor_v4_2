import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/pricelist_scanner_service.dart';
import 'outfitter_package_creator_screen.dart';

/// Persistent Scanned Price List Log / History view.
///
/// Renders a reactive list of the authenticated outfitter's past AI-scanned
/// price lists (sourced from the `scanned_pricelists` Firestore collection,
/// scoped by `outfitterId`). Each entry shows the scan date, source farm,
/// item count, and total value (incl. 7.5% platform fee). A details sheet lets
/// the outfitter view the full parsed species/line-item breakdown, re-export
/// the price list as a shareable summary, or jump to the package publisher to
/// apply the scanned prices to an active package.
class ScannedPriceListHistoryScreen extends StatefulWidget {
  final ThemeController theme;

  const ScannedPriceListHistoryScreen({super.key, required this.theme});

  @override
  State<ScannedPriceListHistoryScreen> createState() =>
      _ScannedPriceListHistoryScreenState();
}

class _ScannedPriceListHistoryScreenState
    extends State<ScannedPriceListHistoryScreen> {
  final PricelistScannerService _pricelistService =
      PricelistScannerService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Scan History Log',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _pricelistService.getMyPriceListsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: widget.theme.accentColor),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final priceLists = snapshot.data ?? [];

          if (priceLists.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
            itemCount: priceLists.length,
            itemBuilder: (context, index) {
              return _ScanHistoryCard(
                data: priceLists[index],
                theme: widget.theme,
                onDelete: () => _confirmDelete(priceLists[index]),
                onViewDetails: () => _showDetailsSheet(priceLists[index]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              size: 64,
              color: widget.theme.subtitleColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Scanned Price Lists Yet',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI-scanned price lists will appear here once you scan a paper price list. '
              'Each scan is stored persistently so you can review, re-export, or apply '
              'scanned prices to active packages at any time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.theme.subtitleColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              'Could not load scan history',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If this persists, the required Firestore composite index '
              '(scanned_pricelists: outfitterId ASC + status ASC + createdAt DESC) '
              'may still be building.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.theme.subtitleColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailsSheet(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ScanDetailsSheet(
        data: data,
        theme: widget.theme,
        onReExport: () {
          Navigator.pop(context);
          _reExportSummary(data);
        },
        onApplyToPackage: () {
          Navigator.pop(context);
          _applyToPackage(data);
        },
      ),
    );
  }

  /// Re-exports the scanned price list as a shareable text summary
  /// (the project's invoice/export pipeline is PDF-based and lives on the
  /// bookings flow; for a raw price list we present a formatted summary the
  /// outfitter can copy/share).
  void _reExportSummary(Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>? ?? []).cast<Map>();
    final buffer = StringBuffer()
      ..writeln('JAGSPOOR — SCANNED PRICE LIST EXPORT')
      ..writeln('=====================================')
      ..writeln('Farm: ${data['farmName'] ?? 'Unknown'}')
      ..writeln('Scanned: ${_formatDate(data['createdAt'])}')
      ..writeln('Source: ${data['sourceImage'] ?? 'unknown'}')
      ..writeln('Items: ${data['totalItems'] ?? items.length}')
      ..writeln('Platform fee: 7.5%')
      ..writeln('=====================================');
    double baseTotal = 0;
    for (final item in items) {
      final name = item['name'] ?? 'Unknown';
      final base = (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
      final display = (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ??
          base * 1.075;
      baseTotal += base;
      buffer.writeln(
          '$name — Base R${base.toStringAsFixed(2)} | Hunter R${display.toStringAsFixed(2)}');
    }
    buffer.writeln('=====================================');
    buffer.writeln(
        'Base total: R${baseTotal.toStringAsFixed(2)}');
    buffer.writeln(
        'Total incl. 7.5% fee: R${(baseTotal * 1.075).toStringAsFixed(2)}');

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.theme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price List Export',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 400),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  buffer.toString(),
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('CLOSE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyToPackage(Map<String, dynamic> data) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scanned prices for "${data['farmName'] ?? 'farm'}" loaded — '
          'use them as a reference when building an active package.',
        ),
        backgroundColor: widget.theme.accentColor,
      ),
    );
    // Navigate to the package publisher where the outfitter can use the
    // scanned species prices as a reference when building an active package.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OutfitterPackageCreatorScreen(theme: widget.theme),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text(
          'Archive Scan?',
          style: TextStyle(color: widget.theme.textColor),
        ),
        content: Text(
          'This scanned price list will be archived (soft-deleted). '
          'You can still re-scan the document later.',
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
            child: const Text('ARCHIVE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _pricelistService.deletePriceList(data['id'] as String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Scan archived'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ Failed to archive: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    try {
      final dt = timestamp is DateTime
          ? timestamp
          : timestamp.toDate();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Unknown date';
    }
  }
}

/// A single scan history entry card.
class _ScanHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ThemeController theme;
  final VoidCallback onDelete;
  final VoidCallback onViewDetails;

  const _ScanHistoryCard({
    required this.data,
    required this.theme,
    required this.onDelete,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final totalItems = (data['totalItems'] as num?)?.toInt() ?? 0;
    final items = (data['items'] as List<dynamic>? ?? []);
    double baseTotal = 0;
    for (final item in items) {
      baseTotal +=
          (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
    }
    final grandTotal = baseTotal * 1.075;
    final farmName = data['farmName'] as String? ?? data['farmId'] as String?;
    final status = data['status'] as String? ?? 'active';

    final statusColor = status == 'active' ? Colors.green : Colors.grey;

    return Card(
      color: theme.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onViewDetails,
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
                    child: Icon(Icons.document_scanner_rounded,
                        color: theme.accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farmName ?? 'Unknown farm',
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
                          _formatDate(data['createdAt']),
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.toUpperCase(),
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
                    Expanded(
                      child: _MetricChip(
                        label: 'ITEMS',
                        value: '$totalItems',
                        theme: theme,
                      ),
                    ),
                    Expanded(
                      child: _MetricChip(
                        label: 'BASE TOTAL',
                        value:
                            'R ${baseTotal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        theme: theme,
                      ),
                    ),
                    Expanded(
                      child: _MetricChip(
                        label: 'INCL. 7.5%',
                        value:
                            'R ${grandTotal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        theme: theme,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.accentColor,
                        side: BorderSide(
                            color: theme.accentColor.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('VIEW DETAILS',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.archive_outlined, size: 20),
                    color: Colors.red.withValues(alpha: 0.7),
                    tooltip: 'Archive scan',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          Colors.red.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    try {
      final dt = timestamp is DateTime
          ? timestamp
          : timestamp.toDate();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Unknown date';
    }
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;
  final bool highlight;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.theme,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? theme.accentColor : theme.textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.subtitleColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Details bottom sheet for a single scanned price list — shows the full
/// parsed species/line-item breakdown (base price, 7.5% commission, hunter
/// display price) plus re-export and apply-to-package actions.
class _ScanDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final ThemeController theme;
  final VoidCallback onReExport;
  final VoidCallback onApplyToPackage;

  const _ScanDetailsSheet({
    required this.data,
    required this.theme,
    required this.onReExport,
    required this.onApplyToPackage,
  });

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List<dynamic>? ?? []);
    final totalItems = (data['totalItems'] as num?)?.toInt() ?? items.length;
    final farmName = data['farmName'] as String? ?? 'Unknown farm';

    double baseTotal = 0;
    double commissionTotal = 0;
    double displayTotal = 0;
    for (final item in items) {
      final base =
          (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
      final display = (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ??
          base * 1.075;
      baseTotal += base;
      displayTotal += display;
      commissionTotal += (display - base);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        color: theme.backgroundColor,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.subtitleColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
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
                        Text(
                          'Scanned Price List',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$farmName • $totalItems items',
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 13,
                          ),
                        ),
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

            // Summary row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCell(
                        label: 'Base Total',
                        value:
                            'R ${baseTotal.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        theme: theme,
                      ),
                    ),
                    Expanded(
                      child: _SummaryCell(
                        label: '7.5% Fee',
                        value:
                            'R ${commissionTotal.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        theme: theme,
                        color: Colors.amber.shade700,
                      ),
                    ),
                    Expanded(
                      child: _SummaryCell(
                        label: 'Hunter Total',
                        value:
                            'R ${displayTotal.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        theme: theme,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Items list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final name = item['name'] ?? 'Unknown';
                  final base =
                      (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
                  final display =
                      (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ??
                          base * 1.075;
                  final commission = display - base;
                  return _DetailItemRow(
                    index: index + 1,
                    name: name.toString(),
                    basePrice: base,
                    commission: commission,
                    displayPrice: display,
                    theme: theme,
                  );
                },
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReExport,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.accentColor,
                        side: BorderSide(
                            color: theme.accentColor.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('RE-EXPORT',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: onApplyToPackage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('APPLY TO PACKAGE',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;
  final Color? color;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.theme,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.subtitleColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? theme.textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _DetailItemRow extends StatelessWidget {
  final int index;
  final String name;
  final double basePrice;
  final double commission;
  final double displayPrice;
  final ThemeController theme;

  const _DetailItemRow({
    required this.index,
    required this.name,
    required this.basePrice,
    required this.commission,
    required this.displayPrice,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'R ${basePrice.toStringAsFixed(0)}',
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: theme.subtitleColor,
                ),
              ),
              Text(
                'R ${displayPrice.toStringAsFixed(0)}',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
