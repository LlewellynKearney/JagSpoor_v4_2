import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Add / edit one predator record of a camp.
///
/// Predators never contribute LSU / GU / BU to the veld calculation — they are
/// recorded purely to report prey impact, which the calculator produces from
/// the species' published daily intake.
class VeldCarryPredatorFormScreen extends StatefulWidget {
  const VeldCarryPredatorFormScreen({
    super.key,
    required this.farmId,
    required this.campId,
    this.existingEntry,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String campId;

  /// Null for a new predator record.
  final PredatorEntry? existingEntry;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryPredatorFormScreen> createState() =>
      _VeldCarryPredatorFormScreenState();
}

class _VeldCarryPredatorFormScreenState
    extends State<VeldCarryPredatorFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  final _countController = TextEditingController();
  final _preyWeightController = TextEditingController();

  /// The 12 predator species from the constants table, in published order.
  static final List<String> _predatorNames =
      VeldCarryConstants.predatorDailyIntakeKg.keys.toList(growable: false);

  String _predatorName = _predatorNames.first;
  bool _saving = false;

  bool get _isEditing => widget.existingEntry != null;

  double get _dailyIntakeKg =>
      VeldCarryConstants.predatorDailyIntakeFor(_predatorName) ?? 0;

  int get _count => (double.tryParse(_countController.text.trim()) ?? 0).round();

  double get _avgPreyWeightKg =>
      double.tryParse(_preyWeightController.text.trim()) ??
      PredatorEntry.defaultAvgPreyWeightKg;

  double get _previewPreyKg => preyKgPerYear(_count, _dailyIntakeKg);
  double get _previewPreyAnimals =>
      preyAnimalsPerYear(_previewPreyKg, _avgPreyWeightKg);

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    if (entry != null) {
      _predatorName = _predatorNames.contains(entry.predatorName)
          ? entry.predatorName
          : _predatorNames.first;
      _countController.text = entry.count.toString();
      _preyWeightController.text = _formatNumber(entry.avgPreyWeightKg);
    } else {
      _preyWeightController.text =
          _formatNumber(PredatorEntry.defaultAvgPreyWeightKg);
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _preyWeightController.dispose();
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
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      _snack('You must be signed in to save a predator.',
          Colors.red.shade700);
      return;
    }

    final entry = PredatorEntry(
      id: widget.existingEntry?.id ?? VeldCarryRepository.newId(),
      campId: widget.campId,
      predatorName: _predatorName,
      count: _count,
      dailyIntakeKg: _dailyIntakeKg,
      avgPreyWeightKg: _avgPreyWeightKg,
      createdAt: widget.existingEntry?.createdAt,
      updatedAt: DateTime.now(),
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _repository.savePredatorEntry(
          uid, widget.farmId, widget.campId, entry);
      if (!mounted) return;
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('$_predatorName saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not save predator: $e'),
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
          _isEditing ? 'Edit Predator' : 'Add Predator',
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
                _banner(theme),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldPredatorSpeciesField'),
                      value: _predatorName,
                      isExpanded: true,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Predator *',
                      ),
                      items: [
                        for (final name in _predatorNames)
                          DropdownMenuItem(
                            value: name,
                            child: Text(
                              name,
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
                                () => _predatorName = value ?? _predatorName,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      key: const ValueKey('veldPredatorIntakeLabel'),
                      children: [
                        Expanded(
                          child: Text(
                            'Daily intake',
                            style: TextStyle(
                              color: OutfitterUi.subtitleColor(theme),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '${_formatNumber(_dailyIntakeKg)} kg/day',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldPredatorCountField'),
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Count *',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null) return 'Enter a number.';
                        if (parsed < 0) return 'Count cannot be negative.';
                        if (parsed != parsed.roundToDouble()) {
                          return 'Enter a whole number.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldPredatorPreyWeightField'),
                      controller: _preyWeightController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Average prey weight (kg)',
                        hintText: 'Default 50 kg',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null) return 'Enter a weight.';
                        if (parsed <= 0) return 'Weight must be above zero.';
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _previewCard(theme),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('veldPredatorSaveButton'),
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
                      _saving ? 'SAVING…' : 'SAVE PREDATOR',
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

  Widget _banner(ThemeController theme) {
    return Container(
      key: const ValueKey('veldPredatorInfoBanner'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: theme.isDarkMode ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: theme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Predators do NOT count in veld capacity — shown for prey impact '
              'only.',
              style: TextStyle(
                color: theme.isDarkMode ? Colors.white : OutfitterUi.lightBody,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(ThemeController theme) {
    return Container(
      key: const ValueKey('veldPredatorPreview'),
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'PREY IMPACT PREVIEW', theme: theme),
          const SizedBox(height: 10),
          _previewRow(
            theme,
            'Prey per year',
            '${_previewPreyKg.toStringAsFixed(0)} kg',
            key: const ValueKey('veldPredatorPreyKgPreview'),
          ),
          _previewRow(
            theme,
            'Prey animals per year',
            _previewPreyAnimals.toStringAsFixed(0),
            key: const ValueKey('veldPredatorPreyAnimalsPreview'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(
    ThemeController theme,
    String label,
    String value, {
    Key? key,
  }) {
    return Padding(
      key: key,
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
