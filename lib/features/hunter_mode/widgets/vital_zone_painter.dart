import 'package:flutter/material.dart';

/// Central offline vital anatomy geometric definitions for precision shot placement.
/// Renders species-specific vital zone overlays with stance-based perspective skew.
class VitalZonePainter extends CustomPainter {
  final String species;
  final double scale;
  final Offset offset;
  final String stanceAngle; // Options: 'Broadside', 'Quartering-Towards', 'Quartering-Away'

  VitalZonePainter({
    required this.species,
    required this.scale,
    required this.offset,
    this.stanceAngle = 'Broadside',
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    
    final Paint lungPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final Paint heartPaint = Paint()
      ..color = Colors.deepOrange.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final Paint bonePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * scale
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    
    // 🎯 ANGLE COMPENSATOR MODIFIERS
    double skewX = 0.0;
    double scaleX = 1.0;
    double organShiftX = 0.0;

    if (stanceAngle == 'Quartering-Towards') {
      skewX = -0.15;      // Lean the anatomical stack into perspective
      scaleX = 0.85;      // Horizontally compress due to foreshortening
      organShiftX = 10.0 * scale; // Shift heart forward relative to camera view
    } else if (stanceAngle == 'Quartering-Away') {
      skewX = 0.15;       // Reverse lean angle perspective
      scaleX = 0.80;      // Compress lung envelope profile
      organShiftX = -12.0 * scale; // Shift vital pocket backward behind rib cage
    }

    // Apply the structural perspective layout transformations to the canvas matrix context
    canvas.transform(Matrix4.skewX(skewX).storage);
    
    double r = 40.0 * scale * scaleX; 

    if (species == 'Kudu') {
      canvas.drawCircle(Offset((-20 * scale) + organShiftX, -10 * scale), r * 1.4, lungPaint);
      canvas.drawCircle(Offset((-10 * scale) + organShiftX, 20 * scale), r * 0.6, heartPaint);
      // Bone line transforms laterally based on perspective stance modifiers
      double boneOffset = stanceAngle == 'Quartering-Towards' ? 15.0 : (stanceAngle == 'Quartering-Away' ? -15.0 : 0.0);
      canvas.drawLine(Offset((-40 * scale) + boneOffset, -60 * scale), Offset((-20 * scale) + boneOffset, 30 * scale), bonePaint);
    } else if (species == 'Warthog') {
      canvas.drawCircle(Offset((-30 * scale) + organShiftX, 15 * scale), r * 0.9, lungPaint);
      canvas.drawCircle(Offset((-25 * scale) + organShiftX, 35 * scale), r * 0.4, heartPaint);
      double boneOffset = stanceAngle == 'Quartering-Towards' ? 10.0 : (stanceAngle == 'Quartering-Away' ? -10.0 : 0.0);
      canvas.drawLine(Offset((-45 * scale) + boneOffset, -20 * scale), Offset((-30 * scale) + boneOffset, 40 * scale), bonePaint);
    } else if (species == 'Impala') {
      canvas.drawCircle(Offset((-15 * scale) + organShiftX, 0), r * 1.1, lungPaint);
      canvas.drawCircle(Offset((-5 * scale) + organShiftX, 20 * scale), r * 0.5, heartPaint);
      double boneOffset = stanceAngle == 'Quartering-Towards' ? 12.0 : (stanceAngle == 'Quartering-Away' ? -12.0 : 0.0);
      canvas.drawLine(Offset((-35 * scale) + boneOffset, -40 * scale), Offset((-15 * scale) + boneOffset, 25 * scale), bonePaint);
    } else {
      // Default: Plains Game (Impala-sized)
      canvas.drawCircle(Offset((-15 * scale) + organShiftX, 0), r * 1.1, lungPaint);
      canvas.drawCircle(Offset((-5 * scale) + organShiftX, 20 * scale), r * 0.5, heartPaint);
      double boneOffset = stanceAngle == 'Quartering-Towards' ? 12.0 : (stanceAngle == 'Quartering-Away' ? -12.0 : 0.0);
      canvas.drawLine(Offset((-35 * scale) + boneOffset, -40 * scale), Offset((-15 * scale) + boneOffset, 25 * scale), bonePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VitalZonePainter oldDelegate) {
    return oldDelegate.species != species ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.stanceAngle != stanceAngle;
  }
}

/// Helper widget to render the vital zone overlay
class VitalZoneOverlay extends StatelessWidget {
  final String species;
  final double scale;
  final Offset offset;
  final String stanceAngle;

  const VitalZoneOverlay({
    super.key,
    required this.species,
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.stanceAngle = 'Broadside',
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: VitalZonePainter(
        species: species,
        scale: scale,
        offset: offset,
        stanceAngle: stanceAngle,
      ),
      size: Size.infinite,
    );
  }
}

/// Species list for dropdown selection
class VitalZoneSpecies {
  static const List<String> supportedSpecies = [
    'Kudu',
    'Impala',
    'Warthog',
    'Blue Wildebeest',
    'Gemsbok',
    'Waterbuck',
    'Bushbuck',
    'Sable Antelope',
    'Eland',
  ];

  static String getDisplayName(String speciesKey) {
    switch (speciesKey) {
      case 'Blue Wildebeest':
        return 'Blue Wildebeest';
      case 'Gemsbok':
        return 'Gemsbok (Oryx)';
      case 'Waterbuck':
        return 'Waterbuck';
      case 'Bushbuck':
        return 'Bushbuck';
      case 'Sable Antelope':
        return 'Sable Antelope';
      case 'Eland':
        return 'Eland';
      default:
        return speciesKey;
    }
  }
}
