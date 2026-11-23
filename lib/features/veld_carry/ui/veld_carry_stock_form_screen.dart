import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Add / edit one species row of a camp's stock ledger.
///
/// Only species with an authorised average weight are offered — a placeholder
/// row (`avgWeightKg == 0`) would produce a meaningless 0 LSU, so it must not
/// appear in the picker. The four present-only species (Baboon / Vervet /
/// Porcupine / Aardvark) are selectable but are recorded with `isCounted =
/// false`, so the [StockEntry] factory forces their LSU / GU / BU totals to
/// zero.
class VeldCarryStockFormScreen extends StatefulWidget {
  const VeldCarryStockFormScreen({
    super.key,
    required this.farmId,
    required this.campId,
    this.existingEntry,
    this.existingSpecies = const [],
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String campId;

  /// Null for a new stock row.
  final StockEntry? existingEntry;

  /// Species names already recorded against the camp, used to block a
  /// duplicate row (the camp keeps one row per species).
  final List<String> existingSpecies;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryStockFormScreen> createState() =>
      _VeldCarryStockFormScreenState();
}

class _VeldCarryStockFormScreenState extends State<VeldCarryStockFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  final _countController = TextEditingController();
  final _weightController = TextEditingController();
  final _grazerController = TextEditingController();
  final _browserController = TextEditingController();

  /// Every species the picker may offer: an authorised weight is required.
  static final List<SpeciesDefault> _selectableSpecies =
      veldCarrySelectableStockSpecies();

  String? _selectedSpeciesName;
  String _feedingClass = StockEntry.feedingClassMixed;
  bool _isPresentOnly = false;
  bool _saving = false;

  bool get _isEditing => widget.existingEntry != null;

  SpeciesDefault? get _selectedSpecies =>
      speciesDefaultFor(_selectedSpeciesName);

  /// True when the chosen species already has a row on this camp and the user
  /// is not editing that same row.
  bool get _isDuplicate {
    if (_isEditing) return false;
    final name = (_selectedSpeciesName ?? '').trim().toLowerCase();
    if (name.isEmpty) return false;
    final editingName =
        (widget.existingEntry?.speciesName ?? '').trim().toLowerCase();
    if (name == editingName) return false;
    return widget.existingSpecies
        .any((species) => species.trim().toLowerCase() == name);
  }

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    if (entry != null) {
      _selectedSpeciesName = entry.speciesName;
      _feedingClass = entry.feedingClass;
      _isPresentOnly = !entry.isCounted;
      _countController.text = entry.count.toString();
      _weightController.text = _formatNumber(entry.avgWeightKg);
      _grazerController.text = _formatNumber(entry.grazerPct);
      _browserController.text = _formatNumber(entry.browserPct);
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _weightController.dispose();
    _grazerController.dispose();
    _browserController.dispose();
    super.dispose();
  }

  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _onSpeciesChanged(String? name) {
    final species = speciesDefaultFor(name);
    setState(() {
      _selectedSpeciesName = name;
      if (species != null) {
        _weightController.text = _formatNumber(species.avgWeightKg);
        _grazerController.text = _formatNumber(species.grazerPct);
        _browserController.text = _formatNumber(species.browserPct);
        _feedingClass = StockEntry.normalizeFeedingClass(species.feedingClass);
        _isPresentOnly = !species.isCounted;
      }
    });
  }

  double get _count => double.tryParse(_countController.text.trim()) ?? 0;
  double get _weight => double.tryParse(_weightController.text.trim()) ?? 0;
  double get _grazer => double.tryParse(_grazerController.text.trim()) ?? 0;
  double get _browser => double.tryParse(_browserController.text.trim()) ?? 0;

  bool get _splitSumsToOne => (_grazer + _browser - 1.0).abs() < 1e-6;

  /// The live preview uses the same calculator helpers the totals use.
  double get _previewWeight =>
      _isPresentOnly ? 0.0 : totalWeightKg(_count.round(), _weight);
  double get _previewLsu =>
      _isPresentOnly ? 0.0 : totalLsu(_count.round(), lsuPerAnimal(_weight));
  double get _previewGu =>
      _isPresentOnly ? 0.0 : totalGu(_count.round(), guPerAnimal(_weight, _grazer));
  double get _previewBu => _isPresentOnly
      ? 0.0
      : totalBu(_count.round(), buPerAnimal(_weight, _browser));

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isDuplicate) {
      _snack('Already recorded — edit it instead.', Colors.orange.shade800);
      return;
    }
    if (!_isPresentOnly && !_splitSumsToOne) {
      _snack('Grazer % + browser % must add up to 1.0.', Colors.red.shade700);
      return;
    }
    final species = _selectedSpecies;
    if (species == null) {
      _snack('Choose a species first.', Colors.orange.shade800);
      return;
    }
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      _snack('You must be signed in to save stock.', Colors.red.shade700);
      return;
    }

    final weight = _weight;
    final entry = StockEntry(
      // One row per species: the species name is the document id so a later
      // edit of the same species can never create a second row.
      id: widget.existingEntry?.id ?? _slug(species.speciesName),
      campId: widget.campId,
      speciesName: species.speciesName,
      scientificName: species.scientificName.isEmpty
          ? null
          : species.scientificName,
      feedingClass: _feedingClass,
      count: _count.round(),
      avgWeightKg: weight,
      grazerPct: _grazer,
      browserPct: _browser,
      // The factory derives isCounted from the species name and zeroes the
      // totals for a present-only species — never re-implemented here.
      isCounted: !_isPresentOnly,
      isOmnivore: _isPresentOnly ? true : null,
      lsuPerAnimal: lsuPerAnimal(weight),
      guPerAnimal: guPerAnimal(weight, _grazer),
      buPerAnimal: buPerAnimal(weight, _browser),
      createdAt: widget.existingEntry?.createdAt,
      updatedAt: DateTime.now(),
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _repository.saveStockEntry(uid, widget.farmId, widget.campId, entry);
      if (!mounted) return;
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${speciesDisplayName(species.speciesName)} saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not save stock: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Stock' : 'Add Stock',
          style: TextStyle(
            color: OutfitterUi.titleColor(theme),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding:
                  SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
              children: [
                _card(
                  theme,
                  children: [
                    Text(
                      'SPECIES',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldStockSpeciesField'),
                      value: _selectedSpeciesName,
                      isExpanded: true,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Species *',
                      ),
                      items: [
                        for (final species in _selectableSpecies)
                          DropdownMenuItem(
                            value: species.speciesName,
                            child: Text(
                              '${species.displayName} · '
                              '${species.scientificName} · '
                              '${_formatNumber(species.avgWeightKg)} kg',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                      onChanged: _saving ? null : _onSpeciesChanged,
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Choose a species.'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _readOnlyChip(
                          theme,
                          icon: Icons.restaurant_rounded,
                          label: _feedingClassLabel(_feedingClass),
                        ),
                      ],
                    ),
                    if (_isDuplicate) ...[
                      const SizedBox(height: 10),
                      _banner(
                        theme,
                        icon: Icons.info_outline_rounded,
                        color: Colors.orange.shade800,
                        text: 'Already recorded — edit it instead.',
                      ),
                    ],
                    if (_isPresentOnly) ...[
                      const SizedBox(height: 10),
                      _banner(
                        theme,
                        key: const ValueKey('veldStockPresentOnlyBanner'),
                        icon: Icons.visibility_outlined,
                        color: Colors.blueGrey.shade700,
                        text: 'Present, not counted — this species is recorded '
                            'for information only and adds 0 LSU to the camp.',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _numberField(
                      theme,
                      key: const ValueKey('veldStockCountField'),
                      controller: _countController,
                      label: 'Count *',
                      decimal: false,
                      validator: (value) {
                        final parsed =
                            double.tryParse((value ?? '').trim());
                        if (parsed == null) return 'Enter a number.';
                        if (parsed < 0) return 'Count cannot be negative.';
                        if (parsed != parsed.roundToDouble()) {
                          return 'Enter a whole number of animals.';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _numberField(
                      theme,
                      key: const ValueKey('veldStockWeightField'),
                      controller: _weightController,
                      label: 'Average weight (kg) *',
                      decimal: true,
                      validator: (value) {
                        final parsed =
                            double.tryParse((value ?? '').trim());
                        if (parsed == null) return 'Enter a weight.';
                        if (parsed <= 0) return 'Weight must be above zero.';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numberField(
                            theme,
                            key: const ValueKey('veldStockGrazerField'),
                            controller: _grazerController,
                            label: 'Grazer fraction *',
                            decimal: true,
                            helper: '0 – 1',
                            onChanged: (_) => setState(() {}),
                            validator: _fractionValidator,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numberField(
                            theme,
                            key: const ValueKey('veldStockBrowserField'),
                            controller: _browserController,
                            label: 'Browser fraction *',
                            decimal: true,
                            helper: '0 – 1',
                            onChanged: (_) => setState(() {}),
                            validator: _fractionValidator,
                          ),
                        ),
                      ],
                    ),
                    if (!_isPresentOnly && !_splitSumsToOne) ...[
                      const SizedBox(height: 8),
                      Text(
                        key: const ValueKey('veldStockSplitError'),
                        'Grazer + browser must add up to 1.0 '
                        '(currently ${(_grazer + _browser).toStringAsFixed(2)}).',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _previewCard(theme),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('veldStockSaveButton'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _saving ? 'SAVING…' : 'SAVE STOCK',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const CopyrightFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _fractionValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter 0 – 1.';
    if (parsed < 0 || parsed > 1) return 'Use 0 – 1.';
    return null;
  }

  Widget _previewCard(ThemeController theme) {
    return Container(
      key: const ValueKey('veldStockPreview'),
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'LIVE PREVIEW', theme: theme),
          const SizedBox(height: 4),
          Text(
            'Calculated for you — never entered by hand.',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _previewRow(theme, 'Total weight',
              '${_previewWeight.toStringAsFixed(1)} kg'),
          _previewRow(theme, 'Total LSU', formatLsu(_previewLsu)),
          _previewRow(theme, 'Grazer units', formatLsu(_previewGu)),
          _previewRow(theme, 'Browser units', formatLsu(_previewBu)),
        ],
      ),
    );
  }

  Widget _previewRow(ThemeController theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(
    ThemeController theme, {
    Key? key,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: theme.isDarkMode ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.isDarkMode ? Colors.white : color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyChip(
    ThemeController theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.accentColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    ThemeController theme, {
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool decimal,
    String? helper,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: OutfitterUi.inputDecoration(
        theme,
        labelText: label,
        hintText: helper,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _card(ThemeController theme, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// The species the stock picker may offer.
///
/// A placeholder row (`avgWeightKg == 0`) is awaiting authorised data and
/// would produce a meaningless 0 LSU, so it is excluded. Public so the
/// exclusion contract is testable without opening the dropdown.
List<SpeciesDefault> veldCarrySelectableStockSpecies() => speciesDefaults
    .where((species) => species.avgWeightKg > 0)
    .toList(growable: false);

String _feedingClassLabel(String feedingClass) {
  switch (StockEntry.normalizeFeedingClass(feedingClass)) {
    case StockEntry.feedingClassGrazer:
      return 'Grazer';
    case StockEntry.feedingClassBrowser:
      return 'Browser';
    case StockEntry.feedingClassOmnivore:
      return 'Omnivore';
    case StockEntry.feedingClassMixed:
    default:
      return 'Mixed feeder';
  }
}

/// Stable document id for a species row (`Greater Kudu` -> `greater_kudu`).
String _slug(String value) {
  final normalised = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalised.isEmpty ? VeldCarryRepository.newId() : normalised;
}

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
