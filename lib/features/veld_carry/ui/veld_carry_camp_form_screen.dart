import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Create / edit one veld camp.
///
/// Pops `true` after a successful save so the camp list can refresh. GPS
/// coordinates are captured for internal mapping only and are never rendered
/// on this form — the operator sees "Location set" / "Not set".
class VeldCarryCampFormScreen extends StatefulWidget {
  const VeldCarryCampFormScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.existingCamp,
    this.theme,
    this.repository,
  });

  final String farmId;
  final String? farmName;

  /// Null for a new camp.
  final Camp? existingCamp;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  @override
  State<VeldCarryCampFormScreen> createState() =>
      _VeldCarryCampFormScreenState();
}

class _VeldCarryCampFormScreenState extends State<VeldCarryCampFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();
  final _districtController = TextEditingController();
  final _townController = TextEditingController();
  final _normController = TextEditingController();
  final _rainfallController = TextEditingController();
  final _notesController = TextEditingController();

  String? _province;
  String? _veldType;
  String _veldCondition = Camp.veldConditionGood;

  double? _lat;
  double? _lng;
  double? _locationAccuracyM;
  DateTime? _locationUpdatedAt;
  String _locationSource = Camp.locationSourceManual;

  bool _locating = false;
  bool _saving = false;

  bool get _isEditing => widget.existingCamp != null;

  bool get _hasLocation => _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    final camp = widget.existingCamp;
    if (camp != null) {
      _nameController.text = camp.name;
      _sizeController.text = _formatNumber(camp.totalSizeHa);
      _province = VeldCarryConstants.provinces.contains(camp.province)
          ? camp.province
          : null;
      _districtController.text = camp.district;
      _townController.text = camp.nearestTown ?? '';
      _veldType = VeldCarryConstants.veldTypes.contains(camp.veldType)
          ? camp.veldType
          : null;
      _veldCondition = Camp.normalizeVeldCondition(camp.veldCondition);
      _normController.text = _formatNumber(camp.deptNormHaPerLsu);
      _rainfallController.text = camp.rainfallMmPerYear == null
          ? ''
          : _formatNumber(camp.rainfallMmPerYear!);
      _notesController.text = camp.notes ?? '';
      _lat = camp.lat;
      _lng = camp.lng;
      _locationAccuracyM = camp.locationAccuracyM;
      _locationUpdatedAt = camp.locationUpdatedAt;
      _locationSource = camp.locationSource;
    } else {
      // A new camp starts on the province-agnostic default; the norm is
      // prefilled as soon as a province is chosen.
      _normController.text = '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    _districtController.dispose();
    _townController.dispose();
    _normController.dispose();
    _rainfallController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _snack(String message, {Color? color}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  void _onProvinceChanged(String? province) {
    setState(() {
      _province = province;
      final suggested =
          VeldCarryConstants.suggestedHaPerLsuForProvince(province);
      // Prefill on every province change; the outfitter can override the
      // value afterwards.
      if (suggested != null) {
        _normController.text = _formatNumber(suggested);
      }
    });
  }

  Future<void> _updateLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locating = false);
        _snack(
          'Location permission denied — enter district manually',
          color: Colors.orange.shade800,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locationAccuracyM = position.accuracy;
        _locationUpdatedAt = DateTime.now();
        _locationSource = Camp.locationSourceGps;
        _locating = false;
      });
      _snack('Location updated', color: Colors.green.shade700);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _snack(
        'Could not read GPS location — enter district manually.',
        color: Colors.orange.shade800,
      );
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      _snack('You must be signed in to save a camp.', color: Colors.red);
      return;
    }

    final deptNorm = double.tryParse(_normController.text.trim()) ?? 0;
    final rainfallText = _rainfallController.text.trim();
    final camp = Camp(
      id: widget.existingCamp?.id ?? VeldCarryRepository.newId(),
      farmId: widget.farmId,
      name: _nameController.text.trim(),
      totalSizeHa: double.tryParse(_sizeController.text.trim()) ?? 0,
      province: _province ?? '',
      district: _districtController.text.trim(),
      nearestTown: _townController.text.trim().isEmpty
          ? null
          : _townController.text.trim(),
      lat: _lat,
      lng: _lng,
      locationAccuracyM: _locationAccuracyM,
      locationUpdatedAt: _locationUpdatedAt,
      locationSource: _locationSource,
      veldType: _veldType ?? '',
      veldCondition: _veldCondition,
      deptNormHaPerLsu: deptNorm,
      // The condition-adjusted norm is calculator output, not UI arithmetic.
      effectiveHaPerLsu: effectiveHaPerLsu(deptNorm, _veldCondition),
      rainfallMmPerYear:
          rainfallText.isEmpty ? null : double.tryParse(rainfallText),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: widget.existingCamp?.createdAt,
      updatedAt: DateTime.now(),
    );

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _repository.saveCamp(uid, camp);
      if (!mounted) return;
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Camp "${camp.name}" saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not save camp: $e'),
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
          _isEditing ? 'Edit Veld Camp' : 'Add Veld Camp',
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
                if (widget.farmName != null && widget.farmName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.farmName!,
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                _card(
                  theme,
                  children: [
                    TextFormField(
                      key: const ValueKey('veldCampNameField'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Camp name *',
                        hintText: 'e.g. North Camp',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Camp name is required.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldCampSizeField'),
                      controller: _sizeController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Total size (ha) *',
                        suffixText: 'ha',
                      ),
                      validator: _positiveNumberValidator('Total size'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldCampProvinceField'),
                      value: _province,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Province *',
                      ),
                      dropdownColor: OutfitterUi.cardColor(theme),
                      style: TextStyle(color: theme.textColor),
                      items: VeldCarryConstants.provinces
                          .map((province) => DropdownMenuItem(
                                value: province,
                                child: Text(province),
                              ))
                          .toList(growable: false),
                      onChanged: _onProvinceChanged,
                      validator: (value) =>
                          value == null ? 'Province is required.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldCampDistrictField'),
                      controller: _districtController,
                      textCapitalization: TextCapitalization.words,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'District *',
                        hintText: 'e.g. Waterberg',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'District is required.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldCampTownField'),
                      controller: _townController,
                      textCapitalization: TextCapitalization.words,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Nearest town (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('veldCampVeldTypeField'),
                      value: _veldType,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Veld type *',
                      ),
                      dropdownColor: OutfitterUi.cardColor(theme),
                      style: TextStyle(color: theme.textColor),
                      items: VeldCarryConstants.veldTypes
                          .map((veldType) => DropdownMenuItem(
                                value: veldType,
                                child: Text(veldType),
                              ))
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _veldType = value),
                      validator: (value) =>
                          value == null ? 'Veld type is required.' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  theme,
                  children: [
                    VeldCarrySectionLabel(
                      label: 'VELD CONDITION',
                      theme: theme,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      key: const ValueKey('veldCampConditionSelector'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: Camp.veldConditionGood,
                          label: Text('Good'),
                          icon: Icon(Icons.eco_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: Camp.veldConditionFair,
                          label: Text('Fair'),
                          icon: Icon(Icons.grass_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: Camp.veldConditionPoor,
                          label: Text('Poor'),
                          icon: Icon(Icons.warning_amber_rounded, size: 16),
                        ),
                      ],
                      selected: {_veldCondition},
                      onSelectionChanged: (selection) => setState(
                        () => _veldCondition = selection.first,
                      ),
                      style: ButtonStyle(
                        foregroundColor: WidgetStatePropertyAll(
                          theme.textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('veldCampNormField'),
                      controller: _normController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Dept. norm (ha per LSU) *',
                        suffixText: 'ha/LSU',
                        hintText: 'Prefilled from the province',
                      ),
                      validator: _positiveNumberValidator('Departmental norm'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Prefilled from the province norm. Override it with your '
                      'own camp figure if you have one.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('veldCampRainfallField'),
                      controller: _rainfallController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Rainfall (mm per year, optional)',
                        suffixText: 'mm',
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return null;
                        final parsed = double.tryParse(text);
                        if (parsed == null || parsed < 0) {
                          return 'Enter a valid rainfall figure.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  theme,
                  children: [
                    VeldCarrySectionLabel(
                      label: 'LOCATION',
                      theme: theme,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _hasLocation
                              ? Icons.gps_fixed_rounded
                              : Icons.gps_off_rounded,
                          size: 18,
                          color: _hasLocation
                              ? Colors.green.shade700
                              : OutfitterUi.subtitleColor(theme),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasLocation ? 'Location set' : 'Not set',
                          style: TextStyle(
                            color: _hasLocation
                                ? Colors.green.shade800
                                : OutfitterUi.subtitleColor(theme),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (_hasLocation && _locationUpdatedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Location updated — accuracy '
                        '${(_locationAccuracyM ?? 0).toStringAsFixed(0)}m, '
                        '${DateFormat('d MMM yyyy HH:mm').format(_locationUpdatedAt!)}',
                        style: TextStyle(
                          color: OutfitterUi.subtitleColor(theme),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('veldCampUpdateLocationButton'),
                        onPressed: _locating ? null : _updateLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(
                          _locating ? 'LOCATING…' : 'LOCATION UPDATE',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GPS is optional. If permission is denied, the district '
                      'and nearest town above are enough.',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  theme,
                  children: [
                    TextFormField(
                      key: const ValueKey('veldCampNotesField'),
                      controller: _notesController,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: OutfitterUi.inputDecoration(
                        theme,
                        labelText: 'Notes (optional)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('veldCampSaveButton'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? 'SAVING…'
                          : (_isEditing ? 'SAVE CHANGES' : 'ADD CAMP'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const CopyrightFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  FormFieldValidator<String> _positiveNumberValidator(String label) {
    return (value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return '$label is required.';
      final parsed = double.tryParse(text);
      if (parsed == null) return 'Enter a valid number.';
      if (parsed <= 0) return '$label must be greater than 0.';
      return null;
    };
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
