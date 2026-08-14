import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/contextual_info_icon.dart';
import 'package:jagspoor/features/hunter_mode/firearm_safe_screen.dart';
import '../data/inventory_bridge.dart';
import '../data/models/optic_profile.dart';
import '../data/models/rifle_profile.dart';
import '../data/scope_calculator.dart';

/// ScopeToolsBottomSheet is the state-of-the-art optical suite: a 4-tab
/// interface covering optic profile configuration (linked to a firearm),
/// zeroing click conversion, SFP reticle scaling, and turret tracking tests.
class ScopeToolsBottomSheet extends StatefulWidget {
  const ScopeToolsBottomSheet({super.key});

  @override
  State<ScopeToolsBottomSheet> createState() => _ScopeToolsBottomSheetState();
}

class _ScopeToolsBottomSheetState extends State<ScopeToolsBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Theme-aware palette sourced from the central tactical theme so the sheet
  // responds to the Day/Night toggle (no hardcoded dark-only colors).
  Color get _tacticalBlack => Theme.of(context).scaffoldBackgroundColor;
  Color get _panelBlack => Theme.of(context).cardColor;
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _accentDim => Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
  Color get _textPrimary => Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFFE0E0E0);
  Color get _textSecondary => Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7) ?? const Color(0xFFB0B0B0);
  Color get _textHint => _textSecondary.withValues(alpha: 0.6);
  static const Color _dangerRed = Color(0xFFD14B3E);
  static const Color _goGreen = Color(0xFF4CAF6A);

  final InventoryBridge _inventoryBridge = InventoryBridge();
  late Stream<List<RifleProfile>> _firearmsStream;

  // Firearm linkage
  String? _selectedRifleId;
  RifleProfile? _selectedRifle;
  OpticProfile _optic = OpticProfile.defaults;
  bool _isSaving = false;

  // Zeroing calculator inputs
  final TextEditingController _verticalCtrl =
      TextEditingController(text: '2.5');
  final TextEditingController _horizontalCtrl =
      TextEditingController(text: '1.2');
  final TextEditingController _zeroDistanceCtrl =
      TextEditingController(text: '175');
  ZeroingResult? _zeroResult;

  // SFP scaling inputs
  final TextEditingController _nativeMagCtrl =
      TextEditingController(text: '10');
  final TextEditingController _currentMagCtrl =
      TextEditingController(text: '6');
  final TextEditingController _nativeHoldCtrl =
      TextEditingController(text: '2');
  SfpScalingResult? _sfpResult;

  // Turret tracking log
  final TextEditingController _dialedCtrl =
      TextEditingController(text: '5');
  final TextEditingController _measuredCtrl =
      TextEditingController(text: '5.2');
  final TextEditingController _trackDistanceCtrl =
      TextEditingController(text: '100');
  final List<TurretTrackingEntry> _trackingLog = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // asBroadcastStream() so the cached stream tolerates multiple listeners
    // and re-subscription (listen → cancel → re-listen) — a raw Firestore
    // snapshots() stream is single-subscription and throws
    // "Bad state: Stream has already been listened to" if its StreamBuilder
    // is ever re-mounted while the State persists.
    _firearmsStream = _inventoryBridge.watchSafeFirearms().asBroadcastStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    _zeroDistanceCtrl.dispose();
    _nativeMagCtrl.dispose();
    _currentMagCtrl.dispose();
    _nativeHoldCtrl.dispose();
    _dialedCtrl.dispose();
    _measuredCtrl.dispose();
    _trackDistanceCtrl.dispose();
    super.dispose();
  }

  void _onRifleSelected(List<RifleProfile> rifles, String? rifleId) {
    if (rifleId == null) return;
    final rifle = rifles.where((r) => r.id == rifleId).firstOrNull;
    if (rifle == null) return;
    setState(() {
      _selectedRifleId = rifleId;
      _selectedRifle = rifle;
      // Hydrate from the linked optic (if any), otherwise use the defaults —
      // and stamp the binding so saving persists `firearmId` on the optic map.
      final loaded = rifle.optic ?? OpticProfile.defaults;
      _optic = loaded.copyWith(firearmId: rifleId);
    });
  }

  /// Opens the Digital Firearm Safe so the hunter can register a rifle when
  /// the safe is empty. The safe is a pushed `MaterialPageRoute`; on return
  /// the cached `_firearmsStream` (a Firestore snapshots broadcast) re-emits
  /// the newly-registered firearm automatically — no manual refresh needed.
  void _openFirearmSafe() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const _FirearmSafeShim(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CALCULATIONS
  // ---------------------------------------------------------------------------

  void _computeZeroing() {
    final v = double.tryParse(_verticalCtrl.text) ?? 0;
    final h = double.tryParse(_horizontalCtrl.text) ?? 0;
    final d = double.tryParse(_zeroDistanceCtrl.text) ?? 100;
    setState(() {
      _zeroResult = ScopeCalculator.calculateZeroingClicks(
        verticalInches: v,
        horizontalInches: h,
        distanceYards: d,
        unit: _optic.turretUnit,
        clickValue: _optic.clickValue,
      );
    });
  }

  void _computeSfp() {
    final nativeMag = double.tryParse(_nativeMagCtrl.text) ?? 10;
    final currentMag = double.tryParse(_currentMagCtrl.text) ?? 10;
    final nativeHold = double.tryParse(_nativeHoldCtrl.text) ?? 1;
    setState(() {
      _sfpResult = ScopeCalculator.calculateSfpScaling(
        nativeMagnification: nativeMag,
        currentMagnification: currentMag,
        nativeReticleValue: nativeHold,
        unit: _optic.turretUnit,
        focalPlane: _optic.focalPlane,
      );
    });
  }

  void _logTrackingTest() {
    final dialed = double.tryParse(_dialedCtrl.text) ?? 0;
    final measured = double.tryParse(_measuredCtrl.text) ?? 0;
    final d = double.tryParse(_trackDistanceCtrl.text) ?? 100;
    final result = ScopeCalculator.calculateTrackingError(
      dialedValue: dialed,
      measuredDisplacementInches: measured,
      distanceYards: d,
      unit: _optic.turretUnit,
    );
    setState(() {
      _trackingLog.insert(
        0,
        TurretTrackingEntry(
          dialedValue: dialed,
          measuredInches: measured,
          distanceYards: d,
          result: result,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _saveOptic() async {
    if (_selectedRifleId == null) return;
    setState(() => _isSaving = true);
    final ok = await _inventoryBridge.saveOpticProfile(
      _selectedRifleId!,
      _optic,
    );
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Optic profile saved to ${_selectedRifle?.displayName ?? 'firearm'}.'
              : 'Save failed — check connection.'),
          backgroundColor: ok ? _goGreen : _dangerRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: _tacticalBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildFirearmLink(),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _accentDim, width: 0.5),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: _accent,
                unselectedLabelColor: _textSecondary,
                indicatorColor: _accent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                isScrollable: true,
                tabs: const [
                  Tab(text: 'OPTIC PROFILE'),
                  Tab(text: 'ZERO / CLICKS'),
                  Tab(text: 'SFP SCALING'),
                  Tab(text: 'TURRET TRACK'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOpticProfileTab(),
                  _buildZeroingTab(),
                  _buildSfpTab(),
                  _buildTrackingTab(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  HEADER + FIREARM LINK
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(Icons.center_focus_strong, color: _accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'OPTICAL SUITE',
              style: TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: _textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFirearmLink() {
    return StreamBuilder<List<RifleProfile>>(
      stream: _firearmsStream,
      builder: (context, snapshot) {
        final rifles = snapshot.data ?? [];
        final isEmpty = rifles.isEmpty;
        // Guard the `value:` against an id that no longer exists in the safe
        // (e.g. the firearm was just deleted) — `DropdownButtonFormField`
        // throws if `value` is non-null and not among the items.
        final effectiveValue =
            rifles.any((r) => r.id == _selectedRifleId) ? _selectedRifleId : null;
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _panelBlack,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accentDim.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.link, color: _accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: effectiveValue,
                    isExpanded: true,
                    dropdownColor: _panelBlack,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    hint: Text(
                      isEmpty
                          ? 'No firearms in safe (Add in Firearm Safe)'
                          : 'Link to Firearm',
                      style: TextStyle(
                        color: isEmpty ? _accent : _textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    style: TextStyle(color: _textPrimary, fontSize: 13),
                    items: rifles
                        .map((r) => DropdownMenuItem<String>(
                              value: r.id,
                              child: Text(
                                r.displayName,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: isEmpty
                        ? null
                        : (id) => _onRifleSelected(rifles, id),
                  ),
                ),
              ),
              if (isEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Open Digital Firearm Safe',
                  icon: Icon(Icons.add_circle_rounded, color: _accent, size: 20),
                  onPressed: _openFirearmSafe,
                ),
              ] else ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text(_optic.turretUnitLabel,
                      style: TextStyle(
                          fontSize: 11, color: _textPrimary)),
                  backgroundColor: _accent,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  //  TAB 1 — OPTIC PROFILE
  // ---------------------------------------------------------------------------

  Widget _buildOpticProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('Optic Identity'),
          _buildTextFieldCard(
            label: 'Optic Name',
            value: _optic.opticName,
            hint: 'e.g. Vortex Razor HD',
            onChanged: (v) =>
                setState(() => _optic = _optic.copyWith(opticName: v)),
          ),
          const SizedBox(height: 12),
          _buildTextFieldCard(
            label: 'Reticle Type',
            value: _optic.reticleType,
            hint: 'e.g. Mil-Dot',
            dropdown: ReticleTypes.standard,
            onChanged: (v) =>
                setState(() => _optic = _optic.copyWith(reticleType: v)),
          ),
          const SizedBox(height: 20),

          _buildSectionLabel('Optical Configuration'),
          Row(
            children: [
              Expanded(
                child: _buildSegControl(
                  label: 'Focal Plane',
                  options: ReticleTypes.focalPlanes,
                  value: _optic.focalPlaneLabel,
                  onChanged: (v) => setState(() => _optic =
                      _optic.copyWith(
                          focalPlane: v == 'FFP'
                              ? FocalPlane.ffp
                              : FocalPlane.sfp)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSegControl(
                  label: 'Turret Units',
                  options: ReticleTypes.turretUnits,
                  value: _optic.turretUnitLabel,
                  onChanged: (v) {
                    final unit =
                        v == 'MRAD' ? TurretUnit.mrad : TurretUnit.moa;
                    final presets = ReticleTypes.clickPresets[v]!;
                    setState(() => _optic = _optic.copyWith(
                        turretUnit: unit, clickValue: presets.first));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextFieldCard(
            label: 'Click Value (${_optic.turretUnitLabel})',
            value: _optic.clickValue.toString(),
            hint: _optic.clickValueLabel,
            keyboardType: TextInputType.number,
            dropdown: ReticleTypes.clickPresets[_optic.turretUnitLabel]!
                .map((e) => e.toString())
                .toList(),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null) {
                setState(() => _optic = _optic.copyWith(clickValue: d));
              }
            },
          ),
          const SizedBox(height: 20),

          _buildSectionLabel('Mechanical Specs'),
          _buildSliderTile(
            label: 'Tube Diameter',
            value: _optic.tubeDiameterMm,
            unit: 'mm',
            min: 25,
            max: 40,
            divisions: 15,
            onChanged: (v) => setState(
                () => _optic = _optic.copyWith(tubeDiameterMm: v)),
          ),
          _buildSliderTile(
            label: 'Height Over Bore',
            value: _optic.heightOverBoreInches,
            unit: 'in',
            min: 0.5,
            max: 4.0,
            divisions: 35,
            onChanged: (v) => setState(
                () => _optic = _optic.copyWith(heightOverBoreInches: v)),
          ),
          _buildSliderTile(
            label: 'Native Magnification',
            value: _optic.nativeMagnification,
            unit: 'x',
            min: 1,
            max: 25,
            divisions: 24,
            onChanged: (v) => setState(
                () => _optic = _optic.copyWith(nativeMagnification: v)),
          ),
          _buildSliderTile(
            label: 'Current Magnification',
            value: _optic.currentMagnification,
            unit: 'x',
            min: 1,
            max: 25,
            divisions: 24,
            onChanged: (v) => setState(
                () => _optic = _optic.copyWith(currentMagnification: v)),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LINKED OPTIC SUMMARY',
              style: TextStyle(
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          _buildSummaryRow('Firearm', _selectedRifle?.name ?? 'None linked'),
          _buildSummaryRow('Optic', _optic.opticName.isEmpty
              ? '—'
              : _optic.opticName),
          _buildSummaryRow(
              'Tube', '${_optic.tubeDiameterMm.toStringAsFixed(0)} mm'),
          _buildSummaryRow('HOB',
              '${_optic.heightOverBoreInches.toStringAsFixed(2)} in'),
          _buildSummaryRow('Turret',
              '${_optic.turretUnitLabel} • ${_optic.clickValueLabel}'),
          _buildSummaryRow('Plane', _optic.focalPlaneLabel),
          _buildSummaryRow('Reticle', _optic.reticleType),
          _buildSummaryRow(
              'Magnification',
              '${_optic.currentMagnification.toStringAsFixed(0)}x '
              '(native ${_optic.nativeMagnification.toStringAsFixed(0)}x)'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  TAB 2 — ZERO / CLICK CALCULATOR
  // ---------------------------------------------------------------------------

  Widget _buildZeroingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSectionLabel('Point-of-Impact Displacement')),
              ContextualInfoIcon(
                title: 'Turret Click Math',
                description:
                    'Converts the observed point-of-impact displacement into the exact turret clicks needed to correct zero. Each scope unit moves the reticle by a fixed angular amount; the displacement is divided by that per-click value to yield clicks.',
                concepts: const [
                  ExplanationConcept(
                    label: '1/4 MOA click',
                    detail: '≈ 0.261" of adjustment at 100 yards (1 MOA ≈ 1.047" @ 100yd).',
                  ),
                  ExplanationConcept(
                    label: '0.1 Mil click',
                    detail: '= 1 cm at 100 metres (1 mil ≈ 10 cm @ 100m), so 0.1 mil moves impact 1 cm per click.',
                  ),
                  ExplanationConcept(
                    label: 'Formula',
                    detail: 'clicks = displacement ÷ per-click-subtension-at-target-distance.',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Positive vertical = impact HIGH. Positive horizontal = impact RIGHT.',
            style: TextStyle(color: _textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _verticalCtrl,
                  label: 'Vertical (in)',
                  icon: Icons.swap_vert,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _horizontalCtrl,
                  label: 'Horizontal (in)',
                  icon: Icons.swap_horiz,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _zeroDistanceCtrl,
            label: 'Target Distance (yards)',
            icon: Icons.straighten,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _computeZeroing,
              icon: const Icon(Icons.calculate),
              label: const Text('CONVERT TO CLICKS',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
          if (_zeroResult != null) _buildZeroResultCard(_zeroResult!),
        ],
      ),
    );
  }

  Widget _buildZeroResultCard(ZeroingResult r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CORRECTION — ${r.unit == TurretUnit.moa ? "MOA" : "MRAD"} turrets',
              style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildDirectionIndicator(
                  label: 'ELEVATION',
                  direction: r.elevationDirection,
                  clicks: r.elevation.clicks,
                  axis: Axis.vertical,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDirectionIndicator(
                  label: 'WINDAGE',
                  direction: r.windageDirection,
                  clicks: r.windage.clicks,
                  axis: Axis.horizontal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _tacticalBlack,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accentDim),
            ),
            child: Row(
              children: [
                Icon(Icons.flag, color: _accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.tacticalString,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('Angular (elev)',
              '${r.elevation.angular.toStringAsFixed(2)} ${r.unit == TurretUnit.moa ? "MOA" : "MRAD"}'),
          _buildSummaryRow('Angular (wind)',
              '${r.windage.angular.toStringAsFixed(2)} ${r.unit == TurretUnit.moa ? "MOA" : "MRAD"}'),
          _buildSummaryRow('Click value', _optic.clickValueLabel),
        ],
      ),
    );
  }

  Widget _buildDirectionIndicator({
    required String label,
    required String direction,
    required int clicks,
    required Axis axis,
  }) {
    final bool isUp = direction == 'UP';
    final bool isDown = direction == 'DOWN';
    final bool isLeft = direction == 'LEFT';
    final bool isRight = direction == 'RIGHT';
    final bool none = direction.isEmpty || clicks == 0;

    final Color color = none
        ? _textHint
        : (isUp || isLeft ? _goGreen : _dangerRed);

    IconData icon;
    if (isUp) {
      icon = Icons.arrow_upward;
    } else if (isDown) {
      icon = Icons.arrow_downward;
    } else if (isLeft) {
      icon = Icons.arrow_back;
    } else if (isRight) {
      icon = Icons.arrow_forward;
    } else {
      icon = Icons.center_focus_strong;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: _textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 6),
          Text(
            none ? 'ON' : '$direction $clicks',
            style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          if (!none)
            Text('CLICKS',
                style: TextStyle(color: color, fontSize: 10, letterSpacing: 1)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  TAB 3 — SFP SCALING
  // ---------------------------------------------------------------------------

  Widget _buildSfpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSectionLabel('Reticle Focal-Plane Scaling')),
              ContextualInfoIcon(
                title: 'SFP Magnification Scaling',
                description:
                    'On a Second Focal Plane (SFP) scope the reticle stays the same physical size as you zoom, so its subtension changes with magnification. Holdover marks are only true at the calibrated magnification; at other powers you must scale the reticle value by the ratio of calibrated to current magnification.',
                concepts: const [
                  ExplanationConcept(
                    label: 'FFP',
                    detail: 'Reticle is true at every magnification — no scaling needed.',
                  ),
                  ExplanationConcept(
                    label: 'SFP',
                    detail: 'Reticle subtension scales inversely with magnification.',
                  ),
                  ExplanationConcept(
                    label: 'Formula',
                    detail: 'trueValue = ratedValue × (calibratedMag ÷ currentMag).',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _optic.focalPlane == FocalPlane.ffp
                ? 'FFP active: reticle is true at ALL magnifications — no scaling needed.'
                : 'SFP active: reticle subtension scales inversely with magnification.',
            style: TextStyle(
                color: _optic.focalPlane == FocalPlane.ffp
                    ? _goGreen
                    : _accent,
                fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _nativeMagCtrl,
                  label: 'Native Mag (x)',
                  icon: Icons.zoom_in,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _currentMagCtrl,
                  label: 'Current Mag (x)',
                  icon: Icons.zoom_out,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _nativeHoldCtrl,
            label: 'Native Reticle Hold (${_optic.turretUnitLabel})',
            icon: Icons.grid_on,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _computeSfp,
              icon: const Icon(Icons.calculate),
              label: const Text('COMPUTE TRUE HOLDOVER',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
          if (_sfpResult != null) _buildSfpResultCard(_sfpResult!),
        ],
      ),
    );
  }

  Widget _buildSfpResultCard(SfpScalingResult r) {
    final unitLabel = r.unit == TurretUnit.moa ? 'MOA' : 'MRAD';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.focalPlane == FocalPlane.ffp ? "FFP" : "SFP"} SCALING RESULT',
              style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tacticalBlack,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accentDim),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TRUE RETICLE VALUE',
                    style: TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                Text(
                    '${r.trueReticleValue.toStringAsFixed(2)} $unitLabel',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(
              'Scaling factor', '${r.scalingFactor.toStringAsFixed(3)}x'),
          _buildSummaryRow(
              'Status',
              r.isScaled
                  ? 'Scaled (non-native magnification)'
                  : 'No scaling required'),
          _buildSummaryRow('Focal plane',
              r.focalPlane == FocalPlane.ffp ? 'FFP' : 'SFP'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  TAB 4 — TURRET TRACKING LOG
  // ---------------------------------------------------------------------------

  Widget _buildTrackingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSectionLabel('Tall-Target Turret Tracking Test')),
              ContextualInfoIcon(
                title: 'Tall-Target Tracking Test',
                description:
                    'A mechanical-accuracy test: dial a known turret value against a measured target displacement and quantify how much the turret deviates from its rated movement. A persistent error indicates a turret-true or click-count problem that must be corrected before relying on dialled corrections in the field.',
                concepts: const [
                  ExplanationConcept(
                    label: 'Tracking error %',
                    detail: 'error = |measured − dialed| ÷ dialed × 100.',
                  ),
                  ExplanationConcept(
                    label: 'Dialled',
                    detail: 'The turret value you entered (in the optic\'s turret unit).',
                  ),
                  ExplanationConcept(
                    label: 'Measured',
                    detail: 'The actual target displacement observed at the known distance.',
                  ),
                  ExplanationConcept(
                    label: 'Pass',
                    detail: '≤ 1% is generally considered acceptable; > 3% warrants service.',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dial a known ${_optic.turretUnitLabel} value, measure the actual target displacement, and verify tracking accuracy.',
            style: TextStyle(color: _textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _dialedCtrl,
                  label: 'Dialed (${_optic.turretUnitLabel})',
                  icon: Icons.tune,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _measuredCtrl,
                  label: 'Measured (in)',
                  icon: Icons.straighten,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _trackDistanceCtrl,
            label: 'Distance (yards)',
            icon: Icons.flag,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _logTrackingTest,
              icon: const Icon(Icons.post_add),
              label: const Text('LOG TRACKING TEST',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
          if (_trackingLog.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Text(
                'No tracking tests logged yet.\nRun a tall-target test to verify turret accuracy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textHint, fontSize: 12),
              ),
            )
          else
            ..._trackingLog.map(_buildTrackingEntryCard),
          if (_trackingLog.length > 1) ...[
            const SizedBox(height: 12),
            _buildAggregateErrorCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackingEntryCard(TurretTrackingEntry e) {
    final r = e.result;
    final color = _qualityColor(r.trackingQuality);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${r.qualityLabel} — ${r.trackingErrorPercent.toStringAsFixed(2)}% error',
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                  '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                  style:
                      TextStyle(color: _textHint, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          _buildSummaryRow('Dialed',
              '${e.dialedValue.toStringAsFixed(1)} ${r.unit == TurretUnit.moa ? "MOA" : "MRAD"}'),
          _buildSummaryRow('Expected',
              '${r.expectedDisplacementInches.toStringAsFixed(2)} in'),
          _buildSummaryRow('Measured',
              '${r.measuredDisplacementInches.toStringAsFixed(2)} in'),
          _buildSummaryRow(
              'Distance', '${e.distanceYards.toStringAsFixed(0)} yd'),
        ],
      ),
    );
  }

  Widget _buildAggregateErrorCard() {
    final avg = _trackingLog
            .map((e) => e.result.trackingErrorPercent)
            .reduce((a, b) => a + b) /
        _trackingLog.length;
    final color = _qualityColor(
        avg <= 1 ? TrackingQuality.excellent : (avg <= 3 ? TrackingQuality.good : (avg <= 5 ? TrackingQuality.fair : TrackingQuality.poor)));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.insights, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Average tracking error across ${_trackingLog.length} tests: ${avg.toStringAsFixed(2)}%',
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Color _qualityColor(TrackingQuality q) {
    switch (q) {
      case TrackingQuality.excellent:
        return _goGreen;
      case TrackingQuality.good:
        return _accent;
      case TrackingQuality.fair:
        return Colors.orange;
      case TrackingQuality.poor:
        return _dangerRed;
    }
  }

  // ---------------------------------------------------------------------------
  //  SHARED UI PRIMITIVES
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: _tacticalBlack,
        border: Border(top: BorderSide(color: _accentDim, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _textSecondary,
                side: BorderSide(color: _accentDim),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CLOSE'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _selectedRifleId == null || _isSaving ? null : _saveOptic,
              icon: _isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _textPrimary))
                  : const Icon(Icons.save),
              label: Text(
                  _selectedRifleId == null ? 'LINK FIREARM FIRST' : 'SAVE OPTIC',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: _textSecondary, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(color: _textSecondary, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: _accent,
              inactiveColor: _accentDim.withValues(alpha: 0.3),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} $unit',
              style: TextStyle(
                  color: _accent, fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegControl({
    required String label,
    required List<String> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: _textSecondary, fontSize: 11)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _tacticalBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accentDim.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: options
                .map((o) => Expanded(
                      child: GestureDetector(
                        onTap: () => onChanged(o),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: value == o ? _accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            o,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: value == o ? _textPrimary : _textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldCard({
    required String label,
    required String value,
    required String hint,
    TextInputType? keyboardType,
    List<String>? dropdown,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentDim.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(color: _textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: dropdown == null
                ? TextField(
                    style: TextStyle(color: _textPrimary, fontSize: 14),
                    controller: TextEditingController(text: value)
                      ..selection = TextSelection.fromPosition(
                          TextPosition(offset: value.length)),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      hintStyle: TextStyle(color: _textHint),
                      border: InputBorder.none,
                    ),
                    keyboardType: keyboardType,
                    onChanged: onChanged,
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdown.contains(value) ? value : dropdown.first,
                      isExpanded: true,
                      dropdownColor: _panelBlack,
                      style: TextStyle(color: _textPrimary, fontSize: 14),
                      items: dropdown
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text(d, style: TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onChanged(v);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.number,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentDim.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(color: _textPrimary, fontSize: 14),
              keyboardType: keyboardType,
              decoration: InputDecoration(
                isDense: true,
                labelText: label,
                labelStyle: TextStyle(color: _textSecondary, fontSize: 11),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single tall-target turret tracking test entry, stored in the session log.
class TurretTrackingEntry {
  final double dialedValue;
  final double measuredInches;
  final double distanceYards;
  final TrackingTestResult result;
  final DateTime timestamp;

  const TurretTrackingEntry({
    required this.dialedValue,
    required this.measuredInches,
    required this.distanceYards,
    required this.result,
    required this.timestamp,
  });
}

/// Shim pushed by the Optical Suite's empty-state "Link to Firearm" action so
/// the hunter can register a rifle without leaving the scope-config flow.
///
/// Resolves the live [ThemeController] (the process-wide singleton constructed
/// in `main()` and mirrored by `ThemeController.instance`) and hosts the real
/// [FirearmSafeScreen] full-screen. On return the cached Firestore
/// `_firearmsStream` broadcast re-emits the newly-registered firearm
/// automatically, so the dropdown populates without a manual reload.
class _FirearmSafeShim extends StatefulWidget {
  const _FirearmSafeShim();

  @override
  State<_FirearmSafeShim> createState() => _FirearmSafeShimState();
}

class _FirearmSafeShimState extends State<_FirearmSafeShim> {
  late final ThemeController _theme;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _theme = ThemeController.instance;
    // Ensure the persisted Day/Night preference is loaded before rendering so
    // the shim matches the app's current mode (no cold-start flash).
    _theme.init().whenComplete(() {
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return FirearmSafeScreen(theme: _theme);
  }
}
