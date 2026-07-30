import 'package:flutter/material.dart';

/// Central offline vital anatomy geometric definitions for precision shot placement.
/// Renders species-specific vital zone overlays with color-coded anatomical structures.
class VitalZonePainter extends CustomPainter {
  final String species;
  final double scale;
  final Offset offset;
  final double shotAngle; // Quartering angle for compensation

  VitalZonePainter({
    required this.species,
    required this.scale,
    required this.offset,
    this.shotAngle = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate center with offset
    final center = Offset(
      size.width / 2 + offset.dx,
      size.height / 2 + offset.dy,
    );

    // Create paints for different anatomical zones
    final Paint lungPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.35) // Red for lethal lung zone
      ..style = PaintingStyle.fill;

    final Paint lungStrokePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale;

    final Paint heartPaint = Paint()
      ..color = Colors.deepOrange.withValues(alpha: 0.5) // Orange heart pocket
      ..style = PaintingStyle.fill;

    final Paint heartStrokePaint = Paint()
      ..color = Colors.deepOrange.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale;

    final Paint bonePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7) // Shoulder/skeletion white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * scale
      ..strokeCap = StrokeCap.round;

    final Paint marginalPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.3) // Orange marginal zone
      ..style = PaintingStyle.fill;

    // Base radius for scaling
    double r = 35.0 * scale;

    // Apply shot angle compensation (quartering)
    // Positive angle = quartering toward, negative = quartering away
    double angleRad = shotAngle * (3.14159 / 180.0);
    double xOffset = 0.0;
    double yOffset = 0.0;
    if (shotAngle != 0) {
      xOffset = (shotAngle.abs() / 90.0) * 15 * scale;
      yOffset = (shotAngle.abs() / 90.0) * 10 * scale;
    }

    // Save canvas state
    canvas.save();

    // Translate to center
    canvas.translate(center.dx, center.dy);

    // Rotate based on shot angle
    if (shotAngle != 0) {
      canvas.rotate(angleRad);
    }

    // Draw species-specific anatomy
    if (species == 'Kudu') {
      _drawKuduAnatomy(
        canvas,
        r,
        xOffset,
        yOffset,
        lungPaint,
        lungStrokePaint,
        heartPaint,
        heartStrokePaint,
        bonePaint,
        marginalPaint,
      );
    } else if (species == 'Warthog') {
      _drawWarthogAnatomy(
        canvas,
        r,
        xOffset,
        yOffset,
        lungPaint,
        lungStrokePaint,
        heartPaint,
        heartStrokePaint,
        bonePaint,
        marginalPaint,
      );
    } else if (species == 'Impala') {
      _drawImpalaAnatomy(
        canvas,
        r,
        xOffset,
        yOffset,
        lungPaint,
        lungStrokePaint,
        heartPaint,
        heartStrokePaint,
        bonePaint,
        marginalPaint,
      );
    } else if (species == 'Zebra') {
      _drawZebraAnatomy(
        canvas,
        r,
        xOffset,
        yOffset,
        lungPaint,
        lungStrokePaint,
        heartPaint,
        heartStrokePaint,
        bonePaint,
        marginalPaint,
      );
    } else {
      // Default: Plains Game (Impala-sized)
      _drawImpalaAnatomy(
        canvas,
        r,
        xOffset,
        yOffset,
        lungPaint,
        lungStrokePaint,
        heartPaint,
        heartStrokePaint,
        bonePaint,
        marginalPaint,
      );
    }

    canvas.restore();
  }

  void _drawKuduAnatomy(
    Canvas canvas,
    double r,
    double xOffset,
    double yOffset,
    Paint lungPaint,
    Paint lungStrokePaint,
    Paint heartPaint,
    Paint heartStrokePaint,
    Paint bonePaint,
    Paint marginalPaint,
  ) {
    // Kudu: Large chest cavity, tall animal
    // Left lung (front quartering)
    canvas.drawCircle(
      Offset(-20 * scale + xOffset, -15 * scale + yOffset),
      r * 1.5,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(-20 * scale + xOffset, -15 * scale + yOffset),
      r * 1.5,
      lungStrokePaint,
    );

    // Right lung
    canvas.drawCircle(
      Offset(5 * scale - xOffset, -10 * scale + yOffset),
      r * 1.3,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(5 * scale - xOffset, -10 * scale + yOffset),
      r * 1.3,
      lungStrokePaint,
    );

    // Heart pocket (between lungs, slightly forward)
    canvas.drawCircle(
      Offset(-5 * scale, 5 * scale),
      r * 0.65,
      heartPaint,
    );
    canvas.drawCircle(
      Offset(-5 * scale, 5 * scale),
      r * 0.65,
      heartStrokePaint,
    );

    // Marginal zone (liver area for quartering shots)
    canvas.drawCircle(
      Offset(10 * scale, 20 * scale),
      r * 0.4,
      marginalPaint,
    );

    // Shoulder blade skeleton line
    canvas.drawLine(
      Offset(-35 * scale, -55 * scale),
      Offset(-15 * scale, 25 * scale),
      bonePaint,
    );

    // Spine reference
    canvas.drawLine(
      Offset(0, -60 * scale),
      Offset(0, 30 * scale),
      bonePaint,
    );
  }

  void _drawWarthogAnatomy(
    Canvas canvas,
    double r,
    double xOffset,
    double yOffset,
    Paint lungPaint,
    Paint lungStrokePaint,
    Paint heartPaint,
    Paint heartStrokePaint,
    Paint bonePaint,
    Paint marginalPaint,
  ) {
    // Warthog: Low, forward vital pocket configuration
    // Front shoulder lung (primary target)
    canvas.drawCircle(
      Offset(-25 * scale + xOffset, 10 * scale + yOffset),
      r * 1.0,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(-25 * scale + xOffset, 10 * scale + yOffset),
      r * 1.0,
      lungStrokePaint,
    );

    // Heart pocket (close to front)
    canvas.drawCircle(
      Offset(-15 * scale, 25 * scale),
      r * 0.5,
      heartPaint,
    );
    canvas.drawCircle(
      Offset(-15 * scale, 25 * scale),
      r * 0.5,
      heartStrokePaint,
    );

    // Shoulder bone
    canvas.drawLine(
      Offset(-40 * scale, -15 * scale),
      Offset(-25 * scale, 35 * scale),
      bonePaint,
    );

    // Brisket area (marginal)
    canvas.drawCircle(
      Offset(-5 * scale, 40 * scale),
      r * 0.35,
      marginalPaint,
    );
  }

  void _drawImpalaAnatomy(
    Canvas canvas,
    double r,
    double xOffset,
    double yOffset,
    Paint lungPaint,
    Paint lungStrokePaint,
    Paint heartPaint,
    Paint heartStrokePaint,
    Paint bonePaint,
    Paint marginalPaint,
  ) {
    // Impala: Standard plains game proportions
    // Left lung
    canvas.drawCircle(
      Offset(-15 * scale + xOffset, -5 * scale + yOffset),
      r * 1.2,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(-15 * scale + xOffset, -5 * scale + yOffset),
      r * 1.2,
      lungStrokePaint,
    );

    // Right lung
    canvas.drawCircle(
      Offset(5 * scale - xOffset, 0),
      r * 1.0,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(5 * scale - xOffset, 0),
      r * 1.0,
      lungStrokePaint,
    );

    // Heart
    canvas.drawCircle(
      Offset(-3 * scale, 15 * scale),
      r * 0.55,
      heartPaint,
    );
    canvas.drawCircle(
      Offset(-3 * scale, 15 * scale),
      r * 0.55,
      heartStrokePaint,
    );

    // Marginal zone
    canvas.drawCircle(
      Offset(8 * scale, 25 * scale),
      r * 0.3,
      marginalPaint,
    );

    // Shoulder blade
    canvas.drawLine(
      Offset(-30 * scale, -35 * scale),
      Offset(-12 * scale, 20 * scale),
      bonePaint,
    );

    // Spine
    canvas.drawLine(
      Offset(0, -40 * scale),
      Offset(0, 25 * scale),
      bonePaint,
    );
  }

  void _drawZebraAnatomy(
    Canvas canvas,
    double r,
    double xOffset,
    double yOffset,
    Paint lungPaint,
    Paint lungStrokePaint,
    Paint heartPaint,
    Paint heartStrokePaint,
    Paint bonePaint,
    Paint marginalPaint,
  ) {
    // Zebra: Horse-sized, similar to horse anatomy
    // Large lung area
    canvas.drawCircle(
      Offset(-20 * scale + xOffset, -10 * scale + yOffset),
      r * 1.6,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(-20 * scale + xOffset, -10 * scale + yOffset),
      r * 1.6,
      lungStrokePaint,
    );

    // Right lung
    canvas.drawCircle(
      Offset(5 * scale - xOffset, -5 * scale + yOffset),
      r * 1.4,
      lungPaint,
    );
    canvas.drawCircle(
      Offset(5 * scale - xOffset, -5 * scale + yOffset),
      r * 1.4,
      lungStrokePaint,
    );

    // Heart (horse-sized)
    canvas.drawCircle(
      Offset(-5 * scale, 10 * scale),
      r * 0.7,
      heartPaint,
    );
    canvas.drawCircle(
      Offset(-5 * scale, 10 * scale),
      r * 0.7,
      heartStrokePaint,
    );

    // Marginal zone
    canvas.drawCircle(
      Offset(10 * scale, 28 * scale),
      r * 0.4,
      marginalPaint,
    );

    // Shoulder blade
    canvas.drawLine(
      Offset(-40 * scale, -50 * scale),
      Offset(-15 * scale, 30 * scale),
      bonePaint,
    );

    // Spine
    canvas.drawLine(
      Offset(0, -55 * scale),
      Offset(0, 35 * scale),
      bonePaint,
    );
  }

  @override
  bool shouldRepaint(covariant VitalZonePainter oldDelegate) {
    return oldDelegate.species != species ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.shotAngle != shotAngle;
  }
}

/// Helper widget to render the vital zone overlay
class VitalZoneOverlay extends StatelessWidget {
  final String species;
  final double scale;
  final Offset offset;
  final double shotAngle;

  const VitalZoneOverlay({
    super.key,
    required this.species,
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.shotAngle = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: VitalZonePainter(
        species: species,
        scale: scale,
        offset: offset,
        shotAngle: shotAngle,
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
    'Zebra',
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
