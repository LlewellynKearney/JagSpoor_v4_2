import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/farm_game_price_entry.dart';
import '../models/farm_service_rate.dart';
import '../../outfitter_mode/widgets/outfitter_scaffold.dart';
import '../services/farm_game_price_csv_importer.dart';
import '../services/farm_game_price_list_manager.dart';
import '../services/farm_price_list_pdf_exporter.dart';
import '../services/outfitter_enterprise_manager.dart';

/// Outfitter "Price List" management screen.
///
/// Lets an outfitter manage the per-farm game price list: pick a farm from a
/// dropdown, view its species entries (species name, qty, price in ZAR), and
/// add / edit / delete entries. Records are persisted in the `farm_pricelists`
/// Firestore collection linked directly to the selected `farmId`.
class OutfitterPriceListScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterPriceListScreen({super.key, required this.theme});

  @override
  State<OutfitterPriceListScreen> createState() =>
      _OutfitterPriceListScreenState();
}

class _OutfitterPriceListScreenState extends State<OutfitterPriceListScreen> {
  final OutfitterEnterpriseManager _enterpriseManager =
      OutfitterEnterpriseManager.instance;
  final FarmGamePriceListManager _priceListManager =
      FarmGamePriceListManager.instance;
  final FarmPriceListPdfExporter _pdfExporter = FarmPriceListPdfExporter();

  List<Map<String, dynamic>> _farms = const [];
  String? _selectedFarmId;
  bool _loadingFarms = true;
  String? _farmsError;

  /// Latest snapshot of the selected farm's itemized service-rate config,
  /// cached from the services StreamBuilder so the PDF exporter can read it
  /// synchronously without re-fetching.
  FarmServiceRates? _currentServiceRates;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    setState(() {
      _loadingFarms = true;
      _farmsError = null;
    });
    try {
      final snap = await _enterpriseManager.getMyFarms();
      if (!mounted) return;
      // `getMyFarms` no longer filters `status == 'active'` server-side (that
      // 3-field equality+equality+orderBy combo required a composite index that
      // is not deployed). Filter active farms client-side here so only active
      // farms appear in the dropdown, while the query itself resolves off the
      // existing `(outfitterId, createdAt)` index. Farms without a `status`
      // field are treated as active (the creator stamps `status: 'active'` on
      // every new farm, so this is the legacy-default-safe choice).
      final farms = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, ...data};
      }).where((f) {
        final status = f['status'] as String?;
        return status == null || status == 'active';
      }).toList();
      setState(() {
        _farms = farms;
        _loadingFarms = false;
        // Preserve the current selection if it still exists; else pick the
        // first farm (so the list is populated immediately when there's only
        // one farm).
        if (_selectedFarmId == null ||
            !farms.any((f) => f['id'] == _selectedFarmId)) {
          _selectedFarmId = farms.isEmpty ? null : farms.first['id'] as String?;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _farmsError = e.toString();
        _loadingFarms = false;
      });
    }
  }

  String? get _selectedFarmName {
    if (_selectedFarmId == null) return null;
    final farm = _farms.firstWhere(
      (f) => f['id'] == _selectedFarmId,
      orElse: () => const {},
    );
    return (farm['name'] as String?) ?? 'Unknown Farm';
  }

  /// Opens the native file picker for a CSV, parses it, and bulk-imports the
  /// valid rows into the currently selected farm's price list. Rows missing a
  /// Species Name or Price are skipped and surfaced in a snackbar.
  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_selectedFarmId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a farm before importing a CSV.'),
        ),
      );
      return;
    }
    final farmId = _selectedFarmId!;
    final outfitterId = _priceListManager.currentUserId ?? '';
    if (outfitterId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You must be signed in to import.')),
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('File picker failed: $e')));
      return;
    }
    if (result == null || result.files.isEmpty) return; // user cancelled
    final picked = result.files.first;
    if (picked.bytes == null && picked.path == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read the selected file.')),
      );
      return;
    }

    // Prefer the in-memory bytes (web / some mobile pickers); fall back to the
    // cached filesystem path.
    String csvContent;
    try {
      if (picked.bytes != null) {
        csvContent = utf8.decode(picked.bytes!);
      } else {
        // ignore: avoid_slow_async_io
        csvContent = await File(picked.path!).readAsString();
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read CSV file: $e')),
      );
      return;
    }

    final parsed = FarmGamePriceCsvImporter.parse(
      csvContent,
      farmId: farmId,
      outfitterId: outfitterId,
    );

    if (parsed.entries.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            parsed.totalRows == 0
                ? 'No rows found in the CSV.'
                : 'No valid rows found. '
                    '${parsed.skippedCount} row(s) skipped '
                    '(missing Species Name or Price).',
          ),
        ),
      );
      return;
    }

    try {
      final created = await _priceListManager.bulkAddEntries(
        farmId: farmId,
        entries: parsed.entries,
      );
      if (!mounted) return;
      final skippedMsg = parsed.hasSkips
          ? '  (${parsed.skippedCount} row(s) skipped: '
              '${parsed.skippedRows.join(', ')})'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('Imported $created entries.$skippedMsg'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Farm Game Price List',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          // High-contrast chips keep the action icons readable against the
          // bright sunrise region of the bushveld background.
          OutfitterActionChip(
            icon: Icons.picture_as_pdf_rounded,
            tooltip: 'Export to PDF',
            iconColor: theme.accentColor,
            onPressed: _exportingPdf ? null : _exportPdf,
          ),
          OutfitterActionChip(
            icon: Icons.upload_file_rounded,
            tooltip: 'Import CSV',
            iconColor: theme.accentColor,
            onPressed: _importCsv,
          ),
          OutfitterActionChip(
            icon: Icons.refresh,
            tooltip: 'Refresh farms',
            iconColor: theme.accentColor,
            onPressed: _loadFarms,
          ),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: _buildBody(),
        ),
      ),
      floatingActionButton: (_selectedFarmId == null)
          ? null
          : FloatingActionButton(
              backgroundColor: theme.accentColor,
              foregroundColor: Colors.white,
              onPressed: () => _showEntrySheet(context),
              tooltip: 'Add species entry',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildBody() {
    final theme = widget.theme;
    if (_loadingFarms) {
      return Center(
        child: CircularProgressIndicator(color: theme.accentColor),
      );
    }
    if (_farmsError != null) {
      return _ErrorState(
        theme: theme,
        message: 'Could not load farms',
        detail: _farmsError!,
        onRetry: _loadFarms,
      );
    }
    if (_farms.isEmpty) {
      return _EmptyFarmsState(theme: theme);
    }
    return SingleChildScrollView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFarmSelector(),
          const SizedBox(height: 16),
          if (_selectedFarmId != null) ...[
            _buildPriceListSection(_selectedFarmId!),
            const SizedBox(height: 16),
            _buildItemizedServicesSection(_selectedFarmId!),
          ] else
            _buildNoFarmSelectedHint(),
          const SizedBox(height: 24),
          const CopyrightFooter(),
        ],
      ),
    );
  }

  Widget _buildFarmSelector() {
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.agriculture, color: theme.accentColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELECT FARM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.subtitleColor,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFarmId,
                    isExpanded: true,
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: theme.cardColor,
                    items: _farms.map((f) {
                      final id = f['id'] as String;
                      final name = (f['name'] as String?) ?? 'Unknown Farm';
                      final district = (f['district'] as String?) ?? '';
                      final label =
                          district.isEmpty ? name : '$name  ·  $district';
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedFarmId = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceListSection(String farmId) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'GAME SPECIES ENTRIES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: theme.subtitleColor,
                ),
              ),
            ),
            Text(
              _selectedFarmName ?? '',
              style: TextStyle(
                fontSize: 12,
                color: theme.subtitleColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<FarmGamePriceEntry>>(
          stream: _priceListManager.getFarmPriceListStream(farmId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: theme.accentColor),
                ),
              );
            }
            if (snap.hasError) {
              return _ErrorState(
                theme: theme,
                message: 'Could not load price list',
                detail: snap.error.toString(),
                onRetry: () => setState(() {}),
              );
            }
            final entries = snap.data ?? const [];
            if (entries.isEmpty) {
              return _EmptyPriceListState(theme: theme);
            }
            return Column(
              children: entries
                  .map((e) => _PriceEntryCard(
                        entry: e,
                        theme: theme,
                        onEdit: () => _showEntrySheet(context, existing: e),
                        onDelete: () => _confirmDelete(e),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoFarmSelectedHint() {
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'Select a farm above to manage its price list.',
          style: TextStyle(color: theme.subtitleColor),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showEntrySheet(BuildContext context, {FarmGamePriceEntry? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PriceEntrySheet(
        theme: widget.theme,
        farmId: _selectedFarmId!,
        existing: existing,
        manager: _priceListManager,
      ),
    );
  }

  Future<void> _confirmDelete(FarmGamePriceEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: Text(
          'Remove "${entry.speciesName}" from this farm\'s price list? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _priceListManager.deleteEntry(entry.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted "${entry.speciesName}".'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  // ── PDF export ────────────────────────────────────────────────────────────

  /// Exports the currently selected farm's game price list + itemized
  /// service rates to a branded PDF and invokes the OS share sheet. Fetches
  /// the latest species list synchronously from Firestore, pairs it with the
  /// cached service rates, and hands both to the [FarmPriceListPdfExporter].
  Future<void> _exportPdf() async {
    if (_selectedFarmId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final farmName = _selectedFarmName ?? 'Unknown Farm';
    final farmId = _selectedFarmId!;

    setState(() => _exportingPdf = true);
    try {
      final species = await _priceListManager.getFarmPriceList(farmId);
      if (!mounted) return;
      await _pdfExporter.generateAndShare(
        farmName: farmName,
        species: species,
        services: _currentServiceRates,
        farmId: farmId,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Price list for "$farmName" exported.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  // ── Itemized services section ───────────────────────────────────────────

  Widget _buildItemizedServicesSection(String farmId) {
    final theme = widget.theme;
    return StreamBuilder<FarmServiceRates>(
      stream: _priceListManager.getFarmServiceRatesStream(farmId),
      builder: (context, snapshot) {
        final rates = snapshot.data;
        if (rates != null) _currentServiceRates = rates;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel('ITEMIZED SERVICES', theme),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting &&
                rates == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: theme.accentColor),
                ),
              )
            else
              ...FarmServiceCategory.all.map((category) {
                final rate = rates?.rate(category.key) ??
                    FarmServiceRate(
                      key: category.key,
                      label: category.label,
                      unitLabel: category.unitLabel,
                      quantityNoun: category.quantityNoun,
                      quantity: 0,
                      pricePerUnit: 0,
                    );
                return _serviceRateRow(theme, category, rate);
              }),
            const SizedBox(height: 4),
            Text(
              'Tap any service to set its quantity & rate. Only services with '
              'a non-zero quantity AND rate are included in the PDF export.',
              style: TextStyle(
                color: theme.subtitleColor,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _serviceRateRow(
    ThemeController theme,
    FarmServiceCategory category,
    FarmServiceRate rate,
  ) {
    final configured = rate.isConfigured;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: configured
              ? theme.accentColor.withValues(alpha: 0.4)
              : theme.accentColor.withValues(alpha: 0.15),
        ),
      ),
      child: ListTile(
        onTap: () => _editServiceRate(category, rate),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          category.label,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 14,
            fontWeight: configured ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: configured
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${rate.quantity} ${category.quantityNoun} × R '
                    '${rate.pricePerUnit.toStringAsFixed(2)} '
                    '(${category.unitLabel.toLowerCase()}) = R '
                    '${rate.total.toStringAsFixed(2)}',
                    style: TextStyle(color: theme.accentColor, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.unitLabel,
                    style: TextStyle(
                      color: theme.subtitleColor,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            : Text(
                '${category.unitLabel} · tap to add ${category.quantityNoun} & rate',
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
        trailing: Icon(
          configured ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
          color: configured ? theme.accentColor : theme.subtitleColor,
          size: 22,
        ),
      ),
    );
  }

  /// Edit sheet for a single service rate (mirrors the Publish Package
  /// line-item editor). Persists via [FarmGamePriceListManager.upsertFarmServiceRate]
  /// (or [removeFarmServiceRate] when cleared).
  void _editServiceRate(
    FarmServiceCategory category,
    FarmServiceRate existing,
  ) {
    final qtyController = TextEditingController(
      text: existing.quantity > 0 ? existing.quantity.toString() : '',
    );
    final priceController = TextEditingController(
      text: existing.pricePerUnit > 0
          ? existing.pricePerUnit.toStringAsFixed(2)
          : '',
    );
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    final farmId = _selectedFarmId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              bottom: true,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: widget.theme.subtitleColor
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        category.label,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rate unit: ${category.unitLabel}',
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: widget.theme.textColor),
                        decoration: InputDecoration(
                          labelText:
                              'Quantity (${category.quantityNoun})',
                          labelStyle:
                              TextStyle(color: widget.theme.subtitleColor),
                          prefixIcon: const Icon(
                              Icons.confirmation_number_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 0) {
                            return 'Enter a valid quantity (0 or more).';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: priceController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: widget.theme.textColor),
                        decoration: InputDecoration(
                          labelText:
                              'Rate — ${category.unitLabel} (ZAR)',
                          labelStyle:
                              TextStyle(color: widget.theme.subtitleColor),
                          prefixIcon: const Icon(Icons.payments_outlined),
                          prefixText: 'R ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        validator: (v) {
                          final n = double.tryParse(v?.trim() ?? '');
                          if (n == null || n < 0) {
                            return 'Enter a valid rate (0 or more).';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (existing.isConfigured)
                            TextButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (farmId == null) return;
                                      try {
                                        await _priceListManager
                                            .removeFarmServiceRate(
                                          farmId: farmId,
                                          key: category.key,
                                        );
                                        if (!ctx.mounted) return;
                                        Navigator.pop(ctx);
                                      } catch (e) {
                                        if (!ctx.mounted) return;
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text('Remove failed: $e'),
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              label: const Text('Remove',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel',
                                style: TextStyle(
                                    color: widget.theme.subtitleColor)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (farmId == null) return;
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    final qty =
                                        int.tryParse(qtyController.text.trim()) ??
                                            0;
                                    final price = double.tryParse(
                                            priceController.text.trim()) ??
                                        0.0;
                                    if (qty <= 0 || price <= 0) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Enter a quantity and rate greater than 0.'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() => saving = true);
                                    try {
                                      await _priceListManager
                                          .upsertFarmServiceRate(
                                        farmId: farmId,
                                        rate: FarmServiceRate(
                                          key: category.key,
                                          label: category.label,
                                          unitLabel: category.unitLabel,
                                          quantityNoun: category.quantityNoun,
                                          quantity: qty,
                                          pricePerUnit: price,
                                        ),
                                      );
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                    } catch (e) {
                                      setSheetState(() => saving = false);
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text('Save failed: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.theme.accentColor,
                              foregroundColor: Colors.white,
                            ),
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('SAVE'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionLabel(String label, ThemeController theme) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: theme.subtitleColor,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry card
// ---------------------------------------------------------------------------

class _PriceEntryCard extends StatelessWidget {
  final FarmGamePriceEntry entry;
  final ThemeController theme;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PriceEntryCard({
    required this.entry,
    required this.theme,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.accentColor.withValues(alpha: 0.15),
            foregroundColor: theme.accentColor,
            child: const Icon(Icons.pets, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.speciesName.isEmpty
                      ? 'Unnamed species'
                      : entry.speciesName,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chip(
                      icon: Icons.confirmation_number,
                      label: 'Qty: ${entry.qty}',
                    ),
                    _chip(
                      icon: Icons.attach_money,
                      label:
                          'R ${entry.priceZAR.toStringAsFixed(2)}',
                    ),
                    if (entry.gender.isNotEmpty && entry.gender != 'Any')
                      _chip(
                        icon: Icons.male,
                        label: entry.gender,
                        iconOverride: _genderIcon(entry.gender),
                      ),
                    if (entry.hornTuskLength.isNotEmpty)
                      _chip(
                        icon: Icons.straighten,
                        label: entry.hornTuskDisplayLabel,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: theme.accentColor, size: 20),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, IconData? iconOverride}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.subtitleColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconOverride ?? icon, size: 13, color: theme.subtitleColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: theme.subtitleColor),
          ),
        ],
      ),
    );
  }

  /// Returns a gender-appropriate icon for the badge (male/female).
  IconData _genderIcon(String gender) {
    switch (gender) {
      case 'Male':
        return Icons.male;
      case 'Female':
        return Icons.female;
      default:
        return Icons.transgender;
    }
  }
}

// ---------------------------------------------------------------------------
// Add / Edit bottom sheet
// ---------------------------------------------------------------------------

class _PriceEntrySheet extends StatefulWidget {
  final ThemeController theme;
  final String farmId;
  final FarmGamePriceEntry? existing;
  final FarmGamePriceListManager manager;

  const _PriceEntrySheet({
    required this.theme,
    required this.farmId,
    required this.manager,
    this.existing,
  });

  @override
  State<_PriceEntrySheet> createState() => _PriceEntrySheetState();
}

class _PriceEntrySheetState extends State<_PriceEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _speciesController;
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  late final TextEditingController _hornTuskController;
  String _gender = FarmGamePriceValidator.defaultGender;
  String _hornTuskUnit = HornTuskUnit.inches;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _speciesController =
        TextEditingController(text: widget.existing?.speciesName ?? '');
    _qtyController =
        TextEditingController(text: widget.existing?.qty.toString() ?? '');
    _priceController = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!.priceZAR == 0
              ? ''
              : widget.existing!.priceZAR.toStringAsFixed(2)),
    );
    _hornTuskController =
        TextEditingController(text: widget.existing?.hornTuskLength ?? '');
    _gender = widget.existing?.gender ?? FarmGamePriceValidator.defaultGender;
    _hornTuskUnit =
        widget.existing?.hornTuskUnit ?? HornTuskUnit.inches;
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    _hornTuskController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final species = _speciesController.text;
    final qty = int.parse(_qtyController.text.trim());
    final price = double.parse(
      _priceController.text.trim().replaceAll(RegExp(r'[Rr ]'), ''),
    );
    final hornTusk = _hornTuskController.text.trim();
    try {
      if (widget.existing == null) {
        await widget.manager.addEntry(
          farmId: widget.farmId,
          speciesName: species,
          qty: qty,
          priceZAR: price,
          gender: _gender,
          hornTuskLength: hornTusk,
          hornTuskUnit: _hornTuskUnit,
        );
      } else {
        await widget.manager.updateEntry(
          entryId: widget.existing!.id,
          speciesName: species,
          qty: qty,
          priceZAR: price,
          gender: _gender,
          hornTuskLength: hornTusk,
          hornTuskUnit: _hornTuskUnit,
        );
      }
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null
                ? 'Added "$species" to the price list.'
                : 'Updated "$species".',
          ),
          backgroundColor: widget.theme.accentColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isEdit = widget.existing != null;
    return SafeArea(
      bottom: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.subtitleColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isEdit ? 'Edit Species Entry' : 'Add Species Entry',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _speciesController,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration(theme, 'Species Name', 'e.g. Impala')
                    .copyWith(prefixIcon: const Icon(Icons.pets)),
                validator: FarmGamePriceValidator.validateSpecies,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration(theme, 'Quantity (qty)', 'e.g. 5')
                    .copyWith(prefixIcon: const Icon(Icons.confirmation_number)),
                validator: FarmGamePriceValidator.validateQty,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.Rr ]')),
                ],
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration(theme, 'Price (ZAR)', 'e.g. 2500')
                    .copyWith(prefixIcon: const Icon(Icons.payments_outlined)),
                validator: FarmGamePriceValidator.validatePrice,
              ),
              const SizedBox(height: 14),
              _buildGenderSelector(theme),
              const SizedBox(height: 14),
              _buildHornTuskField(theme),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving
                        ? 'SAVING...'
                        : (isEdit ? 'SAVE CHANGES' : 'ADD ENTRY'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderSelector(ThemeController theme) {
    return InputDecorator(
      decoration: _inputDecoration(theme, 'Gender', '').copyWith(
        prefixIcon: const Icon(Icons.transgender),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: Theme(
        // Reset the modal's ToggleButtonsTheme so the segmented control uses
        // the colors we set below rather than the app-wide theme.
        data: Theme.of(context).copyWith(toggleButtonsTheme: null),
        child: ToggleButtons(
          isSelected: FarmGamePriceValidator.genderOptions
              .map((g) => g == _gender)
              .toList(),
          onPressed: (index) {
            setState(() {
              _gender = FarmGamePriceValidator.genderOptions[index];
            });
          },
          borderColor: theme.accentColor.withValues(alpha: 0.4),
          selectedBorderColor: theme.accentColor,
          selectedColor: Colors.white,
          fillColor: theme.accentColor,
          color: theme.subtitleColor,
          borderRadius: BorderRadius.circular(8),
          constraints: const BoxConstraints(minHeight: 38, minWidth: 64),
          children: FarmGamePriceValidator.genderOptions
              .map((g) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      g,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  /// Horn / Tusk Length input paired with an inches/cm unit selector.
  /// The text field takes the free-form descriptor (e.g. '28"+', 'Trophy');
  /// the `ToggleButtons` picks the unit, which is persisted on the entry so
  /// the display card can append the correct suffix.
  Widget _buildHornTuskField(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _hornTuskController,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: theme.textColor),
          decoration: _inputDecoration(
            theme,
            'Horn / Tusk Length',
            'e.g. 28", Trophy, Cull',
          ).copyWith(prefixIcon: const Icon(Icons.straighten)),
          validator: FarmGamePriceValidator.validateHornTuskLength,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Unit',
              style: TextStyle(
                color: theme.subtitleColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(toggleButtonsTheme: null),
                child: ToggleButtons(
                  isSelected: HornTuskUnit.options
                      .map((u) => u == _hornTuskUnit)
                      .toList(),
                  onPressed: (index) {
                    setState(() {
                      _hornTuskUnit = HornTuskUnit.options[index];
                    });
                  },
                  borderColor: theme.accentColor.withValues(alpha: 0.4),
                  selectedBorderColor: theme.accentColor,
                  selectedColor: Colors.white,
                  fillColor: theme.accentColor,
                  color: theme.subtitleColor,
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 56),
                  children: HornTuskUnit.options
                      .map((u) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              HornTuskUnit.label(u),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
    ThemeController theme,
    String label,
    String hint,
  ) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: theme.subtitleColor),
      hintStyle: TextStyle(color: theme.subtitleColor.withValues(alpha: 0.5)),
      filled: true,
      fillColor: theme.backgroundColor.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor, width: 1.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

class _EmptyFarmsState extends StatelessWidget {
  final ThemeController theme;
  const _EmptyFarmsState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 24, top: 48),
      child: Column(
        children: [
          Icon(Icons.agriculture, size: 64, color: theme.subtitleColor),
          const SizedBox(height: 16),
          Text(
            'No farms registered yet',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Register a farm in the Farm Control Panel before managing its '
            'price list.',
            style: TextStyle(color: theme.subtitleColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const CopyrightFooter(),
        ],
      ),
    );
  }
}

class _EmptyPriceListState extends StatelessWidget {
  final ThemeController theme;
  const _EmptyPriceListState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.list_alt, size: 48, color: theme.subtitleColor),
          const SizedBox(height: 12),
          Text(
            'No price-list entries yet',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the + button to add your first game species for this farm.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final ThemeController theme;
  final String message;
  final String detail;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.theme,
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.subtitleColor),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}
