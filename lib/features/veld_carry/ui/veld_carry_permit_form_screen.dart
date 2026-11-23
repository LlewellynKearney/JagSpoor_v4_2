import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Add / edit one farm-wide permit.
///
/// Only reachable from [VeldCarryPermitsScreen], which is itself reached solely
/// through `VeldCarryGate` — so with the feature flag OFF none of this UI can
/// appear.
class VeldCarryPermitFormScreen extends StatefulWidget {
  const VeldCarryPermitFormScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.existingPermit,
    this.camps = const [],
    this.theme,
    this.repository,
    this.currentUidOverride,
    this.filePickerOverride,
  });

  final String farmId;
  final String? farmName;

  /// Null for a new permit.
  final FarmPermit? existingPermit;

  /// The farm's camps, offered as the `campIds` multi-select.
  final List<Camp> camps;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  /// Test seam: returns a picked file name (or null when cancelled) so the
  /// attachment flow is testable without a platform file dialog.
  @visibleForTesting
  final Future<String?> Function()? filePickerOverride;

  @override
  State<VeldCarryPermitFormScreen> createState() =>
      _VeldCarryPermitFormScreenState();
}

class _VeldCarryPermitFormScreenState extends State<VeldCarryPermitFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  final _numberController = TextEditingController();
  final _authorityController = TextEditingController();
  final _notesController = TextEditingController();

  /// Only counted species with an authorised weight are offered — a
  /// placeholder row (`avgWeightKg == 0`) would attach a meaningless species.
  static final List<SpeciesDefault> _speciesOptions =
      veldCarryPermitSpeciesOptions();

  String _permitType = FarmPermit.permitTypeCae;
  String _province = VeldCarryConstants.provinces.first;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  final Set<String> _speciesCovered = <String>{};
  final Set<String> _campIds = <String>{};
  String _visibility = FarmPermit.visibilityPrivate;

  /// Attachment NAME only in this phase — see [_pickFile].
  String? _fileName;

  bool _saving = false;

  bool get _isEditing => widget.existingPermit != null;

  @override
  void initState() {
    super.initState();
    final permit = widget.existingPermit;
    if (permit == null) return;
    _permitType = permit.permitType;
    _numberController.text = permit.permitNumber;
    _authorityController.text = permit.issuingAuthority;
    _notesController.text = permit.notes;
    if (permit.province.isNotEmpty) {
      _province = permit.province;
    }
    _issueDate = permit.issueDate;
    _expiryDate = permit.expiryDate;
    _speciesCovered.addAll(permit.speciesCovered);
    _campIds.addAll(permit.campIds);
    _visibility = permit.visibility;
    _fileName = permit.fileName;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _authorityController.dispose();
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

  Future<void> _pickIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 30),
    );
    if (picked == null || !mounted) return;
    setState(() => _issueDate = picked);
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 30),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiryDate = picked);
  }

  /// Picks an attachment and keeps its NAME only.
  ///
  /// TODO(Phase 6): Firebase Storage upload. This phase deliberately stores
  /// `fileName` only — no upload path exists for permit documents yet, and
  /// inventing one would write a `fileUrl` that resolves to nothing.
  Future<void> _pickFile() async {
    try {
      final override = widget.filePickerOverride;
      String? name;
      if (override != null) {
        name = await override();
      } else {
        final result = await FilePicker.platform.pickFiles();
        name = result?.files.isEmpty ?? true ? null : result!.files.first.name;
      }
      if (name == null || name.trim().isEmpty) return;
      if (!mounted) return;
      setState(() => _fileName = name!.trim());
    } catch (e) {
      if (!mounted) return;
      _snack('Could not pick a file: $e', Colors.red.shade700);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      _snack('You must be signed in to save a permit.', Colors.red.shade700);
      return;
    }

    final permit = FarmPermit(
      id: widget.existingPermit?.id ?? VeldCarryRepository.newId(),
      farmId: widget.farmId,
      permitType: _permitType,
      permitNumber: _numberController.text.trim(),
      issuingAuthority: _authorityController.text.trim(),
      province: _province,
      issueDate: _issueDate,
      expiryDate: _expiryDate,
      speciesCovered: _speciesCovered.toList(growable: false),
      campIds: _campIds.toList(growable: false),
      // No file URL in this phase: the attachment is a name only.
      fileUrl: null,
      fileName: _fileName,
      visibility: _visibility,
      notes: _notesController.text.trim(),
      uploadedBy: widget.existingPermit?.uploadedBy.isNotEmpty ?? false
          ? widget.existingPermit!.uploadedBy
          : uid,
      createdAt: widget.existingPermit?.createdAt,
      updatedAt: DateTime.now(),
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _repository.savePermit(uid, widget.farmId, permit);
      if (!mounted) return;
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${permitTypeLabel(permit.permitType)} saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not save permit: $e'),
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
          _isEditing ? 'Edit Permit' : 'Add Permit',
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
                    _label(theme, 'PERMIT'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldPermitTypeField'),
                      value: _permitType,
                      isExpanded: true,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Permit type *',
                      ),
                      items: [
                        for (final type in FarmPermit.permitTypes)
                          DropdownMenuItem(
                            value: type,
                            child: Text(
                              permitTypeLabel(type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _permitType = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey('veldPermitNumberField'),
                      controller: _numberController,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Permit number *',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Permit number is required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey('veldPermitAuthorityField'),
                      controller: _authorityController,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Issuing authority *',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Issuing authority is required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldPermitProvinceField'),
                      value: _province,
                      isExpanded: true,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Province *',
                      ),
                      items: [
                        for (final province in VeldCarryConstants.provinces)
                          DropdownMenuItem(
                            value: province,
                            child: Text(
                              province,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _province = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'VALIDITY'),
                    const SizedBox(height: 8),
                    _dateRow(
                      theme,
                      key: const ValueKey('veldPermitIssueDateField'),
                      label: 'Issue date',
                      value: _issueDate,
                      onPressed: _pickIssueDate,
                    ),
                    const SizedBox(height: 8),
                    _dateRow(
                      theme,
                      key: const ValueKey('veldPermitExpiryDateField'),
                      label: 'Expiry date',
                      value: _expiryDate,
                      onPressed: _pickExpiryDate,
                    ),
                    if (_expiryDate != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          VeldCarryBadge(
                            label: permitStatusLabel(
                              permitStatus(_expiryDate),
                            ),
                            color: permitStatusColor(permitStatus(_expiryDate)),
                            darkMode: theme.isDarkMode,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Expiry drives the badge: amber within 30 days, '
                              'red once past.',
                              style: TextStyle(
                                color: OutfitterUi.subtitleColor(theme),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'SPECIES COVERED'),
                    const SizedBox(height: 4),
                    Text(
                      'Only counted species with an authorised weight are '
                      'offered.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final species in _speciesOptions)
                          FilterChip(
                            key: ValueKey(
                              'veldPermitSpecies_${_slug(species.speciesName)}',
                            ),
                            label: Text(
                              species.displayName,
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected:
                                _speciesCovered.contains(species.speciesName),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _speciesCovered.add(species.speciesName);
                                } else {
                                  _speciesCovered.remove(species.speciesName);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'CAMPS COVERED'),
                    const SizedBox(height: 4),
                    Text(
                      widget.camps.isEmpty
                          ? 'No camps on this farm yet.'
                          : 'Leave empty when the permit covers the whole farm.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                    if (widget.camps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final camp in widget.camps)
                            FilterChip(
                              key: ValueKey('veldPermitCamp_${camp.id}'),
                              label: Text(
                                camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: _campIds.contains(camp.id),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _campIds.add(camp.id);
                                  } else {
                                    _campIds.remove(camp.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'VISIBILITY'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      key: const ValueKey('veldPermitVisibilityField'),
                      segments: const [
                        ButtonSegment<String>(
                          value: FarmPermit.visibilityPrivate,
                          label: Text(
                            'Private',
                            key: ValueKey('veldPermitVisibilityPrivate'),
                            style: TextStyle(fontSize: 12),
                          ),
                          icon: Icon(Icons.lock_outline_rounded, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: FarmPermit.visibilityHunterVisible,
                          label: Text(
                            'Hunter visible',
                            key: ValueKey('veldPermitVisibilityHunterVisible'),
                            style: TextStyle(fontSize: 12),
                          ),
                          icon: Icon(Icons.visibility_outlined, size: 16),
                        ),
                      ],
                      selected: {_visibility},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setState(() => _visibility = selection.first);
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _visibility == FarmPermit.visibilityHunterVisible
                          ? 'Hunters see the permit type, expiry date and '
                              'status only — never the number or the file.'
                          : 'Private: never shown to hunters.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'ATTACHMENT'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('veldPermitPickFileButton'),
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(
                        _fileName == null || _fileName!.isEmpty
                            ? 'Choose file'
                            : _fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.accentColor,
                        side: BorderSide(
                          color: theme.accentColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Stores the file name only for now — document upload '
                      'arrives in Phase 6.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  theme,
                  children: [
                    _label(theme, 'NOTES'),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('veldPermitNotesField'),
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Notes (optional)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('veldPermitSaveButton'),
                  onPressed: _saving ? null : _save,
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
                    _saving ? 'SAVING…' : 'SAVE PERMIT',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                const CopyrightFooter(),
              ],
            ),
          ),
        ),
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

  Widget _label(ThemeController theme, String text) {
    return Text(
      text,
      style: TextStyle(
        color: OutfitterUi.subtitleColor(theme),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _dateRow(
    ThemeController theme, {
    required Key key,
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.textColor,
        alignment: Alignment.centerLeft,
        side: BorderSide(color: OutfitterUi.cardBorderColor(theme)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded, size: 16, color: theme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: ${formatPermitDate(value)}',
              style: TextStyle(color: theme.textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// The species the permit `speciesCovered` picker may offer.
///
/// Counted species with an authorised weight only — a placeholder row
/// (`avgWeightKg == 0`) or a present-only species (baboon, porcupine, ...) is
/// never attached to a permit. Public so the filter is testable without
/// opening the form.
List<SpeciesDefault> veldCarryPermitSpeciesOptions() => speciesDefaults
    .where((species) => species.isCounted && species.avgWeightKg > 0)
    .toList(growable: false);

String _slug(String value) {
  final normalised = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalised.isEmpty ? 'species' : normalised;
}
