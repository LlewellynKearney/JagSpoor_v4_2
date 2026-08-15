import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ballistics/data/inventory_bridge.dart';
import '../../ballistics/data/models/rifle_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/shot_group_analyzer_service.dart';
import '../services/target_session_log_manager.dart';
import '../widgets/shot_group_target_overlay.dart';

/// Dedicated Shot Group Target Analyzer screen.
///
/// Replaces the old mock analyzer with a calibrated pipeline: load / capture
/// a straight-on target photo, optionally auto-detect shot holes, calibrate
/// the scale against a known reference object, mark the point of aim, then
/// compute true extreme spread, mean radius, and center-of-impact offset in
/// MOA or MIL. The linked firearm is selected from the Digital Firearm Safe
/// and the completed session can be saved to the local offline log.
class ShotGroupAnalyzerScreen extends StatefulWidget {
  final ThemeController theme;
  final File? initialImage;

  const ShotGroupAnalyzerScreen({
    super.key,
    required this.theme,
    this.initialImage,
  });

  @override
  State<ShotGroupAnalyzerScreen> createState() =>
      _ShotGroupAnalyzerScreenState();
}

class _ShotGroupAnalyzerScreenState extends State<ShotGroupAnalyzerScreen> {
  static final _svc = ShotGroupAnalyzerService.instance;
  static final _picker = ImagePicker();
  static final _inventoryBridge = InventoryBridge();

  File? _image;
  Size _imageSize = const Size(4, 3);
  bool _decoding = false;

  List<ShotImpact> _shots = [];
  ScaleReference? _reference;
  Offset? _aimPoint;

  // Linked firearm (from the Digital Firearm Safe).
  String? _selectedFirearmId;
  late Stream<List<RifleProfile>> _firearmsStream;
  List<RifleProfile> _lastFirearms = const [];

  // Distance + angular inputs.
  double _distance = 100.0;
  DistanceUnit _distanceUnit = DistanceUnit.yards;
  AngularUnit _angularUnit = AngularUnit.moa;
  double _clickValue = 0.25; // 1/4 MOA (or 0.1 MIL)
  double _refKnownMm = 26.0; // 5-Rand coin default

  ShotGroupAnalysis? _analysis;
  bool _autoDetecting = false;
  bool _savingSession = false;

  @override
  void initState() {
    super.initState();
    // Cache the stream as a broadcast stream so a re-mounting StreamBuilder
    // (theme toggle / parent restructure) never throws "already listened to".
    _firearmsStream = _inventoryBridge.watchSafeFirearms().asBroadcastStream();
    if (widget.initialImage != null) {
      _image = widget.initialImage;
      _loadImageSize();
    }
  }

  Future<void> _loadImageSize() async {
    if (_image == null) return;
    setState(() => _decoding = true);
    final size = await imageSizeOf(_image!);
    if (mounted) {
      setState(() {
        _imageSize = size;
        _decoding = false;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1920, imageQuality: 90);
      await _adoptImage(f);
    } catch (e) {
      _pickerError('Could not pick photo: $e');
    }
  }

  Future<void> _capture() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 1920, imageQuality: 95);
      await _adoptImage(f);
    } catch (e) {
      _pickerError('Camera unavailable: $e');
    }
  }

  void _pickerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _adoptImage(XFile? f) async {
    if (f == null) return;
    setState(() {
      _image = File(f.path);
      _shots = [];
      _reference = null;
      _aimPoint = null;
      _analysis = null;
    });
    await _loadImageSize();
    await _autoDetect();
  }

  Future<void> _autoDetect() async {
    if (_image == null) return;
    setState(() => _autoDetecting = true);
    try {
      final bytes = await _image!.readAsBytes();
      final decoded = _svc.decode(bytes);
      if (decoded != null) {
        final detected = _svc.detectShotHoles(decoded);
        if (mounted) {
          setState(() {
            _shots = detected;
          });
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _autoDetecting = false);
    }
  }

  void _recompute() {
    setState(() {
      _analysis = _svc.analyze(
        shots: _shots,
        pxPerMm: _reference?.pxPerMm ?? 0,
        distance: _distance,
        distanceUnit: _distanceUnit,
        aimPoint: _aimPoint,
        angularUnit: _angularUnit,
      );
    });
  }

  RifleProfile? get _selectedRifle {
    final id = _selectedFirearmId;
    if (id == null) return null;
    for (final r in _lastFirearms) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _saveSession() async {
    final analysis = _analysis;
    if (analysis == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final rifle = _selectedRifle;
    final clicks = _svc.suggestedClicks(analysis, _angularUnit, _clickValue);
    setState(() => _savingSession = true);
    try {
      final id = await TargetSessionLogManager.instance.saveSession(
        analysis: analysis,
        distance: _distance,
        distanceUnit: _distanceUnit,
        angularUnit: _angularUnit,
        clickValue: _clickValue,
        firearmId: rifle?.id ?? '',
        firearmLabel: rifle?.displayName ?? 'Unlinked',
        suggestedUpClicks: clicks.upClicks,
        suggestedRightClicks: clicks.rightClicks,
      );
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(id == null
              ? 'Failed to save target session.'
              : 'Target session saved to offline log.'),
          backgroundColor:
              id == null ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
            content: Text('Failed to save target session: $e'),
            backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _savingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Scaffold(
      backgroundColor: t.backgroundColor,
      appBar: AppBar(
        title: const Text('🎯 Shot Group Target Analyzer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: t.backgroundColor,
        foregroundColor: t.textColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Auto-detect holes',
            onPressed: _image == null || _autoDetecting ? null : _autoDetect,
            icon: _autoDetecting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.accentColor))
                : Icon(Icons.auto_fix_high, color: t.accentColor),
          ),
        ],
      ),
      body: _image == null
          ? SafeArea(child: _emptyState(t))
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: SafeBottomInset.paddingFor(context,
                    horizontal: 12, top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_decoding)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: t.accentColor)),
                      )
                    else if (_imageSize != const Size(4, 3))
                      ShotGroupTargetOverlay(
                        imageFile: _image!,
                        imageSize: _imageSize,
                        initialShots: _shots,
                        initialReference: _reference,
                        initialAimPoint: _aimPoint,
                        analysis: _analysis,
                        onShotsChanged: (s) => _shots = s,
                        onReferenceChanged: (r) => _reference = r,
                        onAimPointChanged: (a) => _aimPoint = a,
                      ),
                    const SizedBox(height: 12),
                    _buildFirearmSelector(t),
                    const SizedBox(height: 8),
                    _configRow(t),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _shots.isEmpty ? null : _recompute,
                        icon: const Icon(Icons.analytics, size: 18),
                        label: const Text('ANALYZE GROUP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accentColor,
                          foregroundColor:
                              t.isDarkMode ? t.textColor : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_analysis != null) ...[
                      _resultsPanel(t, _analysis!),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _savingSession ? null : _saveSession,
                          icon: _savingSession
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: t.accentColor))
                              : const Icon(Icons.save_alt, size: 18),
                          label: Text(_savingSession
                              ? 'SAVING…'
                              : 'SAVE TARGET SESSION'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                t.accentColor.withValues(alpha: 0.18),
                            foregroundColor: t.accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: t.accentColor.withValues(alpha: 0.6)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      floatingActionButton: _image == null
          ? SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'gallery',
                    onPressed: _pickFromGallery,
                    backgroundColor: t.accentColor,
                    foregroundColor: t.isDarkMode ? t.textColor : Colors.white,
                    icon: const Icon(Icons.photo),
                    label: const Text('Gallery'),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.extended(
                    heroTag: 'camera',
                    onPressed: _capture,
                    backgroundColor: t.accentColor,
                    foregroundColor: t.isDarkMode ? t.textColor : Colors.white,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture'),
                  ),
                ],
              ),
            )
          : FloatingActionButton(
              onPressed: _capture,
              backgroundColor: t.accentColor,
              foregroundColor: t.isDarkMode ? t.textColor : Colors.white,
              child: const Icon(Icons.camera_alt),
            ),
    );
  }

  Widget _buildFirearmSelector(ThemeController t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.accentColor.withValues(alpha: 0.3)),
      ),
      child: StreamBuilder<List<RifleProfile>>(
        stream: _firearmsStream,
        builder: (context, snapshot) {
          final firearms = snapshot.data ?? const <RifleProfile>[];
          _lastFirearms = firearms;
          // Guard the value against a just-deleted firearm.
          final effectiveValue = (_selectedFirearmId != null &&
                  firearms.any((r) => r.id == _selectedFirearmId))
              ? _selectedFirearmId
              : null;
          return Row(
            children: [
              Icon(Icons.gpp_good_outlined, size: 18, color: t.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: effectiveValue,
                    isExpanded: true,
                    style: TextStyle(color: t.textColor, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Choose Firearm',
                      hintStyle:
                          TextStyle(color: t.subtitleColor, fontSize: 12),
                    ),
                    items: firearms
                        .map((r) => DropdownMenuItem<String>(
                              value: r.id,
                              child: Text(r.displayName,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: firearms.isEmpty
                        ? null
                        : (id) => setState(() => _selectedFirearmId = id),
                    dropdownColor: t.cardColor,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(ThemeController t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.center_focus_strong_rounded,
                  size: 64, color: t.accentColor.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Load a straight-on target photo',
                  style: TextStyle(
                      color: t.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  'Frame the target paper flat & square. Calibrate the scale '
                  'against a coin or 1-inch grid, then place shot holes to '
                  'compute true extreme spread, mean radius & COI in MOA/MIL.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.subtitleColor, fontSize: 13)),
              const SizedBox(height: 24),
              if (_lastFirearms.isEmpty)
                Text(
                    'No firearms in safe yet — add one in the Digital Firearm '
                    'Safe to link it here.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: t.subtitleColor, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _configRow(ThemeController t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: _field(t, 'Distance', _distance.toStringAsFixed(0), (v) {
                final d = double.tryParse(v);
                if (d != null) setState(() => _distance = d);
              }),
            ),
            const SizedBox(width: 8),
            _segmented<DistanceUnit>(t, _distanceUnit,
                {DistanceUnit.yards: 'yds', DistanceUnit.meters: 'm'},
                (u) => setState(() => _distanceUnit = u)),
            const SizedBox(width: 8),
            _segmented<AngularUnit>(t, _angularUnit,
                {AngularUnit.moa: 'MOA', AngularUnit.mil: 'MIL'},
                (u) => setState(() => _angularUnit = u)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _field(t, 'Click value', _clickValue.toStringAsFixed(2),
                  (v) {
                final c = double.tryParse(v);
                if (c != null) setState(() => _clickValue = c);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                  t, 'Ref length (mm)', _refKnownMm.toStringAsFixed(1), (v) {
                final r = double.tryParse(v);
                if (r != null) setState(() => _refKnownMm = r);
              }),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _field(ThemeController t, String label, String value,
      ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: value,
      keyboardType: TextInputType.number,
      style: TextStyle(color: t.textColor, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.accentColor, fontSize: 10),
        filled: true,
        fillColor: t.backgroundColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.accentColor.withValues(alpha: 0.35)),
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _segmented<T>(ThemeController t, T value, Map<T, String> items,
      ValueChanged<T> onSel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: t.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accentColor.withValues(alpha: 0.35)),
      ),
      child: ToggleButtons(
        isSelected: items.keys.map((k) => k == value).toList(),
        onPressed: (i) => onSel(items.keys.elementAt(i)),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 30),
        borderColor: Colors.transparent,
        selectedColor: t.isDarkMode ? t.textColor : Colors.white,
        fillColor: t.accentColor,
        color: t.subtitleColor,
        children: items.values
            .map((l) => Text(l, style: const TextStyle(fontSize: 11)))
            .toList(),
      ),
    );
  }

  Widget _resultsPanel(ThemeController t, ShotGroupAnalysis a) {
    final unit = _angularUnit.label;
    final calibrated = a.isCalibrated;
    final clicks = _svc.suggestedClicks(a, _angularUnit, _clickValue);
    final dirV = clicks.upClicks >= 0 ? 'UP' : 'DOWN';
    final dirH = clicks.rightClicks >= 0 ? 'RIGHT' : 'LEFT';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_graph, color: t.accentColor, size: 18),
          const SizedBox(width: 6),
          Text('GROUP ANALYSIS',
              style: TextStyle(
                  color: t.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ]),
        const SizedBox(height: 8),
        if (!calibrated)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Scale not calibrated. Use "Calibrate Scale" on the overlay '
                    'and set the reference length to get MOA/MIL.',
                    style: const TextStyle(color: Colors.orange, fontSize: 11)),
              ),
            ]),
          )
        else ...[
          _stat(t, 'Extreme Spread',
              '${a.extremeSpreadMm.toStringAsFixed(1)}mm / ${a.extremeSpreadInches.toStringAsFixed(2)}"',
              '${a.extremeSpreadAngular.toStringAsFixed(2)} $unit'),
          _stat(t, 'Mean Radius', '${a.meanRadiusMm.toStringAsFixed(1)}mm',
              '${a.meanRadiusAngular.toStringAsFixed(2)} $unit'),
          if (a.aimPoint != null) ...[
            _stat(t, 'COI Offset H',
                '${a.offsetHorizontalMm.toStringAsFixed(1)}mm',
                '${a.offsetHorizontalAngular.abs().toStringAsFixed(2)} $unit'),
            _stat(t, 'COI Offset V',
                '${a.offsetVerticalMm.toStringAsFixed(1)}mm',
                '${a.offsetVerticalAngular.abs().toStringAsFixed(2)} $unit'),
            Divider(
                height: 16, color: t.subtitleColor.withValues(alpha: 0.25)),
            Text('Suggested correction (dial opposite to COI):',
                style: TextStyle(color: t.subtitleColor, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
                '${clicks.upClicks.abs()} clicks $dirV  •  ${clicks.rightClicks.abs()} clicks $dirH',
                style: TextStyle(
                    color: t.accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
          Divider(height: 16, color: t.subtitleColor.withValues(alpha: 0.25)),
          Row(children: [
            const Icon(Icons.verified, color: Colors.green, size: 16),
            const SizedBox(width: 6),
            Text(a.precisionCategory(_angularUnit),
                style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ]),
        ],
        const SizedBox(height: 8),
        Text('${a.shots.length} shots detected/placed',
            style: TextStyle(color: t.subtitleColor, fontSize: 10)),
      ]),
    );
  }

  Widget _stat(ThemeController t, String label, String metric, String angular) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(color: t.subtitleColor, fontSize: 11))),
        Expanded(
            flex: 3,
            child: Text(metric,
                style: TextStyle(color: t.textColor, fontSize: 11))),
        Expanded(
            flex: 2,
            child: Text(angular,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: t.accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
