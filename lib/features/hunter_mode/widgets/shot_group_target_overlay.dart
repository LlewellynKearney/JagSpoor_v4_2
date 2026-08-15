import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/shot_group_analyzer_service.dart';

/// Interactive target overlay: renders the target photo with alignment
/// guides, lets the user tap to place / adjust shot impact points, calibrate
/// a two-point scale reference, mark the point of aim (bullseye), and draws
/// the computed extreme-spread line, center of impact, and COI offset.
class ShotGroupTargetOverlay extends StatefulWidget {
  final File imageFile;
  final Size imageSize;
  final List<ShotImpact> initialShots;
  final ScaleReference? initialReference;
  final Offset? initialAimPoint;
  final ShotGroupAnalysis? analysis;
  final ValueChanged<List<ShotImpact>> onShotsChanged;
  final ValueChanged<ScaleReference?> onReferenceChanged;
  final ValueChanged<Offset?> onAimPointChanged;

  const ShotGroupTargetOverlay({
    super.key,
    required this.imageFile,
    required this.imageSize,
    this.initialShots = const [],
    this.initialReference,
    this.initialAimPoint,
    this.analysis,
    required this.onShotsChanged,
    required this.onReferenceChanged,
    required this.onAimPointChanged,
  });

  @override
  State<ShotGroupTargetOverlay> createState() => _ShotGroupTargetOverlayState();
}

/// Interaction mode the overlay is in.
enum _OverlayMode { placeShots, calibrateRefA, calibrateRefB, markAim }

class _ShotGroupTargetOverlayState extends State<ShotGroupTargetOverlay> {
  late List<ShotImpact> _shots;
  ScaleReference? _reference;
  Offset? _refA;
  Offset? _aimPoint;
  _OverlayMode _mode = _OverlayMode.placeShots;
  bool _guidesOn = true;

  // Known length (mm) for the in-progress reference calibration.
  double _refLengthMm = 26.0;

  @override
  void initState() {
    super.initState();
    _shots = List.of(widget.initialShots);
    _reference = widget.initialReference;
    _aimPoint = widget.initialAimPoint;
  }

  Offset _toImageCoords(Offset local, Size renderedSize) {
    final sx = widget.imageSize.width / renderedSize.width;
    final sy = widget.imageSize.height / renderedSize.height;
    return Offset(local.dx * sx, local.dy * sy);
  }

  void _handleTap(Offset local, Size renderedSize) {
    final p = _toImageCoords(local, renderedSize);
    switch (_mode) {
      case _OverlayMode.placeShots:
        setState(() {
          _shots.add(ShotImpact(pixel: p));
          widget.onShotsChanged(_shots);
        });
      case _OverlayMode.calibrateRefA:
        setState(() {
          _refA = p;
          _mode = _OverlayMode.calibrateRefB;
        });
      case _OverlayMode.calibrateRefB:
        if (_refA != null) {
          setState(() {
            _reference = ScaleReference(
                a: _refA!, b: p, knownLengthMm: _refLengthMm);
            widget.onReferenceChanged(_reference);
            _mode = _OverlayMode.placeShots;
          });
        }
      case _OverlayMode.markAim:
        setState(() {
          _aimPoint = p;
          widget.onAimPointChanged(p);
          _mode = _OverlayMode.placeShots;
        });
    }
  }

  void _undoLast() {
    setState(() {
      if (_mode == _OverlayMode.calibrateRefB) {
        _refA = null;
        _mode = _OverlayMode.calibrateRefA;
      } else if (_shots.isNotEmpty) {
        _shots.removeLast();
        widget.onShotsChanged(_shots);
      }
    });
  }

  void _clearShots() {
    setState(() {
      _shots.clear();
      widget.onShotsChanged(_shots);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toolbar(),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: widget.imageSize.width / widget.imageSize.height,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rendered = Size(
                  constraints.maxWidth,
                  constraints.maxWidth /
                      (widget.imageSize.width / widget.imageSize.height),
                );
                return GestureDetector(
                  onTapDown: (d) => _handleTap(d.localPosition, rendered),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(widget.imageFile, fit: BoxFit.fill),
                      CustomPaint(
                        painter: _TargetOverlayPainter(
                          imageSize: widget.imageSize,
                          renderedSize: rendered,
                          shots: _shots,
                          reference: _reference,
                          refPending: _refA,
                          aimPoint: _aimPoint,
                          analysis: widget.analysis,
                          guidesOn: _guidesOn,
                          mode: _mode,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        _modeHint(),
      ],
    );
  }

  Widget _toolbar() {
    final t = ThemeController.instance;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _modeChip('Place Shots', _OverlayMode.placeShots, Icons.gps_fixed, t),
        _modeChip('Calibrate Scale', _OverlayMode.calibrateRefA, Icons.straighten, t),
        _modeChip('Mark Aim', _OverlayMode.markAim, Icons.center_focus_strong, t),
        ActionChip(
          onPressed: () => setState(() => _guidesOn = !_guidesOn),
          avatar: Icon(Icons.grid_on,
              size: 16,
              color: _guidesOn ? t.accentColor : t.subtitleColor),
          label: Text('Guides',
              style: TextStyle(color: t.textColor, fontSize: 11)),
          backgroundColor: t.cardColor,
          side: BorderSide(color: t.accentColor.withValues(alpha: 0.3)),
        ),
        ActionChip(
          onPressed: _undoLast,
          avatar: Icon(Icons.undo, size: 16, color: t.subtitleColor),
          label: Text('Undo',
              style: TextStyle(color: t.textColor, fontSize: 11)),
          backgroundColor: t.cardColor,
          side: BorderSide(color: t.accentColor.withValues(alpha: 0.3)),
        ),
        ActionChip(
          onPressed: _shots.isEmpty ? null : _clearShots,
          avatar: const Icon(Icons.delete_sweep, size: 16, color: Colors.red),
          label: const Text('Clear',
              style: TextStyle(color: Colors.red, fontSize: 11)),
          backgroundColor: t.cardColor,
          side: BorderSide(color: t.accentColor.withValues(alpha: 0.3)),
        ),
      ],
    );
  }

  Widget _modeChip(
      String label, _OverlayMode target, IconData icon, ThemeController t) {
    final selected = _mode == target ||
        (target == _OverlayMode.calibrateRefA &&
            _mode == _OverlayMode.calibrateRefB);
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() {
        _mode = target;
        if (target == _OverlayMode.calibrateRefA) _refA = null;
      }),
      avatar: Icon(icon, size: 16, color: selected ? t.textColor : t.accentColor),
      label: Text(label,
          style: TextStyle(
              color: selected ? t.textColor : t.textColor, fontSize: 11)),
      selectedColor: t.accentColor,
      backgroundColor: t.cardColor,
      side: BorderSide(color: t.accentColor.withValues(alpha: 0.3)),
    );
  }

  Widget _modeHint() {
    final t = ThemeController.instance;
    final (text, color) = switch (_mode) {
      _OverlayMode.placeShots => ('Tap shot holes on the target to place impacts.', t.subtitleColor),
      _OverlayMode.calibrateRefA => ('Tap the first edge of the reference (coin / grid line).', t.accentColor),
      _OverlayMode.calibrateRefB => ('Tap the opposite edge to set the ${_refLengthMm.toStringAsFixed(1)}mm span.', t.accentColor),
      _OverlayMode.markAim => ('Tap the bullseye / point of aim.', Colors.cyan),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 11)),
          ),
          if (_mode == _OverlayMode.calibrateRefA ||
              _mode == _OverlayMode.calibrateRefB)
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    initialValue: _refLengthMm.toStringAsFixed(0),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.textColor, fontSize: 11),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: t.accentColor.withValues(alpha: 0.4)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: t.accentColor),
                      ),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0) {
                        setState(() => _refLengthMm = val);
                      }
                    },
                  ),
                ),
                Text('mm',
                    style: TextStyle(color: t.accentColor, fontSize: 11)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Paints alignment guides, shot markers, reference scale, extreme-spread
/// line, center of impact, and COI-offset vector over the target image.
class _TargetOverlayPainter extends CustomPainter {
  final Size imageSize;
  final Size renderedSize;
  final List<ShotImpact> shots;
  final ScaleReference? reference;
  final Offset? refPending;
  final Offset? aimPoint;
  final ShotGroupAnalysis? analysis;
  final bool guidesOn;
  final _OverlayMode mode;

  _TargetOverlayPainter({
    required this.imageSize,
    required this.renderedSize,
    required this.shots,
    required this.reference,
    required this.refPending,
    required this.aimPoint,
    required this.analysis,
    required this.guidesOn,
    required this.mode,
  });

  double get _sx => renderedSize.width / imageSize.width;
  double get _sy => renderedSize.height / imageSize.height;

  Offset _render(Offset p) => Offset(p.dx * _sx, p.dy * _sy);

  @override
  void paint(Canvas canvas, Size size) {
    // Alignment guides for straight target-paper framing.
    if (guidesOn) {
      final guide = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      // Center crosshair.
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), guide);
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), guide);
      // Rule-of-thirds alignment grid.
      final third = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 0.8;
      for (final i in [1.0, 2.0]) {
        canvas.drawLine(Offset(size.width * i / 3, 0),
            Offset(size.width * i / 3, size.height), third);
        canvas.drawLine(Offset(0, size.height * i / 3),
            Offset(size.width, size.height * i / 3), third);
      }
      // Corner alignment brackets (target-paper framing aid).
      final bracket = Paint()
        ..color = Colors.amber.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      const b = 18.0;
      for (final corner in [
        Offset(0, 0),
        Offset(size.width, 0),
        Offset(0, size.height),
        Offset(size.width, size.height),
      ]) {
        final dx = corner.dx == 0 ? b : -b;
        final dy = corner.dy == 0 ? b : -b;
        canvas.drawLine(corner, corner + Offset(dx, 0), bracket);
        canvas.drawLine(corner, corner + Offset(0, dy), bracket);
      }
    }

    // Calibrated reference scale line.
    if (reference != null) {
      final rp = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final a = _render(reference!.a);
      final b = _render(reference!.b);
      canvas.drawLine(a, b, rp);
      _dot(canvas, a, Colors.amber, 5);
      _dot(canvas, b, Colors.amber, 5);
      _label(canvas, '${reference!.knownLengthMm.toStringAsFixed(1)}mm ref',
          Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - 10), Colors.amber);
    }
    if (refPending != null) {
      _dot(canvas, _render(refPending!), Colors.amber, 5);
    }

    // Point of aim (bullseye).
    if (aimPoint != null) {
      final ap = _render(aimPoint!);
      final aimPaint = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(ap, 10, aimPaint);
      canvas.drawLine(ap - const Offset(14, 0), ap + const Offset(14, 0), aimPaint);
      canvas.drawLine(ap - const Offset(0, 14), ap + const Offset(0, 14), aimPaint);
    }

    // Extreme spread line (between the two farthest shots).
    final a = analysis;
    if (a != null && a.shots.length >= 2 && a.extremeSpreadIndexA >= 0) {
      final p1 = _render(a.shots[a.extremeSpreadIndexA].pixel);
      final p2 = _render(a.shots[a.extremeSpreadIndexB].pixel);
      final es = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p1, p2, es);
    }

    // Center of impact + offset vector to aim point.
    if (a != null && a.shots.isNotEmpty) {
      final coi = _render(a.centerOfImpactPx);
      final coiPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(coi, 4, coiPaint);
      if (aimPoint != null) {
        final ap = _render(aimPoint!);
        final off = Paint()
          ..color = Colors.greenAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(coi, ap, off);
      }
    }

    // Shot markers (numbered).
    for (int i = 0; i < shots.length; i++) {
      final p = _render(shots[i].pixel);
      final ring = Paint()
        ..color = shots[i].autoDetected ? Colors.orangeAccent : Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(p, 7, ring);
      _dot(canvas, p, shots[i].autoDetected ? Colors.orangeAccent : Colors.red, 2);
      _label(canvas, '${i + 1}', p + const Offset(8, -10),
          shots[i].autoDetected ? Colors.orangeAccent : Colors.red);
    }
  }

  void _dot(Canvas canvas, Offset p, Color c, double r) {
    canvas.drawCircle(p, r, Paint()..color = c);
  }

  void _label(Canvas canvas, String text, Offset p, Color c) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TargetOverlayPainter old) =>
      old.shots != shots ||
      old.reference != reference ||
      old.refPending != refPending ||
      old.aimPoint != aimPoint ||
      old.analysis != analysis ||
      old.guidesOn != guidesOn ||
      old.mode != mode;
}

/// Compute the natural pixel size of an image file via a lightweight decode.
/// Used to size the overlay aspect ratio without loading a full widget.
Future<Size> imageSizeOf(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final decoded = ShotGroupAnalyzerService.instance.decode(bytes);
    if (decoded != null) {
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    }
  } catch (_) {}
  return const Size(4, 3);
}
