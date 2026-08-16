import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/farm_game_price_entry.dart';
import '../services/farm_game_price_list_manager.dart';
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

  List<Map<String, dynamic>> _farms = const [];
  String? _selectedFarmId;
  bool _loadingFarms = true;
  String? _farmsError;

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
      final farms = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, ...data};
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

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Farm Game Price List',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: theme.accentColor),
            tooltip: 'Refresh farms',
            onPressed: _loadFarms,
          ),
        ],
      ),
      body: _buildBody(),
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
          if (_selectedFarmId != null)
            _buildPriceListSection(_selectedFarmId!)
          else
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

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.subtitleColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.subtitleColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: theme.subtitleColor),
          ),
        ],
      ),
    );
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
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
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
    try {
      if (widget.existing == null) {
        await widget.manager.addEntry(
          farmId: widget.farmId,
          speciesName: species,
          qty: qty,
          priceZAR: price,
        );
      } else {
        await widget.manager.updateEntry(
          entryId: widget.existing!.id,
          speciesName: species,
          qty: qty,
          priceZAR: price,
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
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                  .copyWith(prefixIcon: const Icon(Icons.attach_money)),
              validator: FarmGamePriceValidator.validatePrice,
            ),
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
