import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Add / edit one planted feed area of a camp.
///
/// The hectares-per-LSU norm is read-only and comes from
/// `VeldCarryConstants.plantedFeedHaPerLsu`; `OTHER_CUSTOM` has no published
/// norm, so the outfitter must supply one for that feed type only. The
/// capacity preview is produced by `plantedCapacityLsu()`.
class VeldCarryPlantedFormScreen extends StatefulWidget {
  const VeldCarryPlantedFormScreen({
    super.key,
    required this.farmId,
    required this.campId,
    this.existingArea,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String campId;

  /// Null for a new planted area.
  final PlantedArea? existingArea;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryPlantedFormScreen> createState() =>
      _VeldCarryPlantedFormScreenState();
}

class _VeldCarryPlantedFormScreenState
    extends State<VeldCarryPlantedFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  final _areaController = TextEditingController();
  final _customNameController = TextEditingController();
  final _customNormController = TextEditingController();
  final _notesController = TextEditingController();

  String _feedType = PlantedArea.feedTypeLucerneIrrigated;
  String _season = PlantedArea.seasonAllYear;
  bool _irrigated = false;
  bool _saving = false;

  bool get _isEditing => widget.existingArea != null;

  bool get _isCustom => _feedType == PlantedArea.feedTypeOtherCustom;

  /// Published norm for the selected feed type, or null for `OTHER_CUSTOM`.
  double? get _publishedHaPerLsu =>
      VeldCarryConstants.plantedHaPerLsuFor(_feedType);

  /// The norm actually used for the preview and the saved area.
  double get _effectiveHaPerLsu {
    final published = _publishedHaPerLsu;
    if (published != null) return published;
    return double.tryParse(_customNormController.text.trim()) ?? 0;
  }

  double get _areaHa => double.tryParse(_areaController.text.trim()) ?? 0;

  double get _previewCapacity => plantedCapacityLsu(_areaHa, _effectiveHaPerLsu);

  @override
  void initState() {
    super.initState();
    final area = widget.existingArea;
    if (area != null) {
      _feedType = area.feedType;
      _season = area.season;
      _irrigated = area.irrigated;
      _areaController.text = _formatNumber(area.areaHa);
      _customNameController.text = area.customName ?? '';
      _notesController.text = area.notes;
      if (area.feedType == PlantedArea.feedTypeOtherCustom) {
        _customNormController.text = _formatNumber(area.haPerLsu);
      }
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _customNameController.dispose();
    _customNormController.dispose();
    _notesController.dispose();
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final haPerLsu = _effectiveHaPerLsu;
    if (haPerLsu <= 0) {
      _snack('A hectares-per-LSU norm is required for this feed type.',
          Colors.orange.shade800);
      return;
    }
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      _snack('You must be signed in to save a planted area.', Colors.red.shade700);
      return;
    }

    final area = PlantedArea(
      id: widget.existingArea?.id ?? VeldCarryRepository.newId(),
      campId: widget.campId,
      feedType: _feedType,
      customName: _isCustom && _customNameController.text.trim().isNotEmpty
          ? _customNameController.text.trim()
          : null,
      areaHa: _areaHa,
      haPerLsu: haPerLsu,
      season: _season,
      irrigated: _irrigated,
      notes: _notesController.text.trim(),
      createdAt: widget.existingArea?.createdAt,
      updatedAt: DateTime.now(),
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _repository.savePlantedArea(
          uid, widget.farmId, widget.campId, area);
      if (!mounted) return;
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${plantedFeedTypeLabel(_feedType)} area saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not save planted area: $e'),
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
          _isEditing ? 'Edit Planted Area' : 'Add Planted Area',
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
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldPlantedFeedTypeField'),
                      value: _feedType,
                      isExpanded: true,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Feed type *',
                      ),
                      items: [
                        for (final type in PlantedArea.feedTypes)
                          DropdownMenuItem(
                            value: type,
                            child: Text(
                              plantedFeedTypeLabel(type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                                () => _feedType =
                                    value ?? PlantedArea.feedTypeOtherCustom,
                              ),
                    ),
                    const SizedBox(height: 10),
                    _readOnlyRow(
                      theme,
                      label: 'Hectares per LSU',
                      value: _publishedHaPerLsu == null
                          ? 'Outfitter-defined'
                          : '${_formatNumber(_publishedHaPerLsu!)} ha/LSU',
                      key: const ValueKey('veldPlantedHaPerLsuLabel'),
                    ),
                    if (_isCustom) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('veldPlantedCustomNormField'),
                        controller: _customNormController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: OutfitterUi.inputDecoration(
                          theme,
                          labelText: 'Custom ha/LSU *',
                          hintText: 'e.g. 1.4',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null) return 'Enter a ha/LSU value.';
                          if (parsed <= 0) return 'Must be above zero.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('veldPlantedCustomNameField'),
                        controller: _customNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: OutfitterUi.inputDecoration(
                          theme,
                          labelText: 'Custom feed name (optional)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldPlantedAreaField'),
                      controller: _areaController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Area (ha) *',
                        hintText: 'e.g. 12.5',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null) return 'Enter the area in hectares.';
                        if (parsed <= 0) return 'Area must be above zero.';
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    VeldCarrySectionLabel(label: 'SEASON', theme: theme),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      key: const ValueKey('veldPlantedSeasonField'),
                      segments: const [
                        ButtonSegment(
                          value: PlantedArea.seasonAllYear,
                          label: Text('All year'),
                        ),
                        ButtonSegment(
                          value: PlantedArea.seasonSummer,
                          label: Text('Summer'),
                        ),
                        ButtonSegment(
                          value: PlantedArea.seasonWinter,
                          label: Text('Winter'),
                        ),
                      ],
                      selected: {_season},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) =>
                              setState(() => _season = selection.first),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Only "All year" areas count towards the year-round '
                      'capacity; seasonal areas are reported separately.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ListTile paints its ink on the nearest Material, so it
                    // needs its own transparent Material inside a decorated
                    // card or the framework asserts the splash is invisible.
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        key: const ValueKey('veldPlantedIrrigatedField'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Irrigated',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: _irrigated,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _irrigated = value),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      key: const ValueKey('veldPlantedNotesField'),
                      controller: _notesController,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Notes (optional)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _previewCard(theme),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('veldPlantedSaveButton'),
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
                      _saving ? 'SAVING…' : 'SAVE PLANTED AREA',
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

  Widget _previewCard(ThemeController theme) {
    return Container(
      key: const ValueKey('veldPlantedPreview'),
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'LIVE PREVIEW', theme: theme),
          const SizedBox(height: 4),
          Text(
            'Capacity = area ÷ hectares per LSU.',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _readOnlyRow(
            theme,
            label: 'Capacity',
            value: formatLsu(_previewCapacity),
            key: const ValueKey('veldPlantedCapacityPreview'),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyRow(
    ThemeController theme, {
    required String label,
    required String value,
    Key? key,
  }) {
    return Row(
      key: key,
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

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
