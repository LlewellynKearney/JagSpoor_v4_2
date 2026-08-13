import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

/// A single detected / placed shot impact, in image pixel coordinates.
class ShotImpact {
  final Offset pixel;
  final bool autoDetected;

  const ShotImpact({required this.pixel, this.autoDetected = false});

  double get x => pixel.dx;
  double get y => pixel.dy;
}

/// Angular unit used to express group size and corrections.
enum AngularUnit { moa, mil }

extension AngularUnitLabel on AngularUnit {
  String get label => this == AngularUnit.moa ? 'MOA' : 'MIL';
}

/// Distance unit the shooter measured the target at.
enum DistanceUnit { yards, meters }

/// A two-point scale reference the user calibrates on the target image
/// (e.g. the diameter of a coin, or one square of a 1-inch grid).
class ScaleReference {
  final Offset a;
  final Offset b;
  final double knownLengthMm;

  const ScaleReference({
    required this.a,
    required this.b,
    required this.knownLengthMm,
  });

  double get pixelLength => (b - a).distance;

  /// Pixels per millimetre derived from the calibrated reference span.
  double get pxPerMm =>
      knownLengthMm > 0 && pixelLength > 0 ? pixelLength / knownLengthMm : 0.0;
}

/// Full statistical breakdown of a shot group on a calibrated target.
class ShotGroupAnalysis {
  /// Shot impacts in pixel coordinates (input).
  final List<ShotImpact> shots;

  /// Calibrated pixels-per-millimetre (0 if uncalibrated).
  final double pxPerMm;

  /// Target distance + unit.
  final double distance;
  final DistanceUnit distanceUnit;

  /// User-marked point of aim (bullseye). Null → COI used as the aim point.
  final Offset? aimPoint;

  /// Centroid (center of impact) in pixels.
  final Offset centerOfImpactPx;

  /// Extreme spread — the greatest distance between any two shots.
  final double extremeSpreadPx;
  final int extremeSpreadIndexA;
  final int extremeSpreadIndexB;

  /// Mean radius — average distance of each shot from the center of impact.
  final double meanRadiusPx;

  /// Angular size of the extreme spread, expressed in [unit].
  final double extremeSpreadAngular;

  /// Angular size of the mean radius, expressed in [unit].
  final double meanRadiusAngular;

  /// Center-of-impact offset from the aim point, expressed as
  /// (horizontal, vertical) in [unit]. Positive horizontal = right; positive
  /// vertical = up (the shooter dials the opposite to correct).
  final double offsetHorizontalAngular;
  final double offsetVerticalAngular;

  const ShotGroupAnalysis({
    required this.shots,
    required this.pxPerMm,
    required this.distance,
    required this.distanceUnit,
    required this.aimPoint,
    required this.centerOfImpactPx,
    required this.extremeSpreadPx,
    required this.extremeSpreadIndexA,
    required this.extremeSpreadIndexB,
    required this.meanRadiusPx,
    required this.extremeSpreadAngular,
    required this.meanRadiusAngular,
    required this.offsetHorizontalAngular,
    required this.offsetVerticalAngular,
  });

  bool get isCalibrated => pxPerMm > 0;

  /// Extreme spread in millimetres (0 if uncalibrated).
  double get extremeSpreadMm =>
      isCalibrated ? extremeSpreadPx / pxPerMm : 0.0;

  /// Extreme spread in inches (0 if uncalibrated).
  double get extremeSpreadInches => extremeSpreadMm / 25.4;

  /// Mean radius in millimetres (0 if uncalibrated).
  double get meanRadiusMm => isCalibrated ? meanRadiusPx / pxPerMm : 0.0;

  /// COI offset in millimetres from the aim point
  /// (right, up) — 0,0 if no aim point marked.
  double get offsetHorizontalMm {
    if (aimPoint == null || !isCalibrated) return 0.0;
    return (centerOfImpactPx.dx - aimPoint!.dx) / pxPerMm;
  }

  double get offsetVerticalMm {
    if (aimPoint == null || !isCalibrated) return 0.0;
    // Image y grows downward; "up" is negative image-y, so invert.
    return (aimPoint!.dy - centerOfImpactPx.dy) / pxPerMm;
  }

  /// Human-readable precision category based on the angular extreme spread.
  String precisionCategory(AngularUnit unit) {
    final moa = unit == AngularUnit.moa
        ? extremeSpreadAngular
        : ShotGroupAnalyzerService.milToMoa(extremeSpreadAngular);
    if (moa < 0.5) return 'Sub-MOA Precision';
    if (moa < 1.0) return '1 MOA Group';
    if (moa < 2.0) return 'Average Group';
    return 'Open Group';
  }
}

/// On-device shot-group target analyzer.
///
/// Performs real (no mock) computer-vision shot-hole detection on a target
/// photo and computes the full statistical group geometry: extreme spread,
/// mean radius, and center-of-impact offset — all calibrated against a
/// user-placed scale reference and converted to true MOA / MIL angular units.
class ShotGroupAnalyzerService {
  ShotGroupAnalyzerService._();
  static final ShotGroupAnalyzerService instance = ShotGroupAnalyzerService._();

  /// Luminance threshold below which a pixel is treated as a potential shot
  /// hole (dark impact mark on light target paper).
  static const double _darkLuminance = 110;

  /// Minimum shot-hole radius (in sampled cells) to be accepted — filters
  /// out dust specks and JPEG noise.
  static const int _minHoleRadiusCells = 2;

  /// Maximum shot-hole radius (in sampled cells) — rejects the reference
  /// coin / large shadows that are far bigger than a bullet hole.
  static const int _maxHoleRadiusCells = 18;

  /// Sample step (px) for the detection raster. Keeps the connected-component
  /// pass O(n/step²) — fast enough for a 1920px photo on a phone.
  static const int _sampleStep = 4;

  /// Decode a target image from raw bytes. Returns null if undecodable.
  img.Image? decode(Uint8List bytes) => img.decodeImage(bytes);

  /// Detect shot-hole candidates on the target via dark-blob detection.
  ///
  /// Uses a luminance threshold + 4-connected component labelling on a
  /// sampled grid, then keeps components whose size and circularity fall in
  /// the bullet-hole range. Each accepted blob's centroid becomes a shot
  /// impact point (in full-resolution pixel coordinates).
  List<ShotImpact> detectShotHoles(img.Image image) {
    final w = image.width;
    final h = image.height;
    final gw = (w / _sampleStep).ceil();
    final gh = (h / _sampleStep).ceil();

    // Rasterize luminance to a dark-mask grid.
    final mask = List<List<bool>>.generate(gh, (_) => List.filled(gw, false));
    for (int gy = 0; gy < gh; gy++) {
      for (int gx = 0; gx < gw; gx++) {
        final x = (gx * _sampleStep).clamp(0, w - 1);
        final y = (gy * _sampleStep).clamp(0, h - 1);
        final p = image.getPixelSafe(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum < _darkLuminance) mask[gy][gx] = true;
      }
    }

    // 4-connected component labelling.
    final labels = List<List<int>>.generate(gh, (_) => List.filled(gw, 0));
    final components = <int, _Blob>{};
    int nextLabel = 1;
    for (int gy = 0; gy < gh; gy++) {
      for (int gx = 0; gx < gw; gx++) {
        if (!mask[gy][gx] || labels[gy][gx] != 0) continue;
        // BFS flood fill.
        final queue = <math.Point<int>>[math.Point(gx, gy)];
        labels[gy][gx] = nextLabel;
        int sumX = 0, sumY = 0, count = 0;
        int minX = gx, maxX = gx, minY = gy, maxY = gy;
        while (queue.isNotEmpty) {
          final p = queue.removeLast();
          sumX += p.x;
          sumY += p.y;
          count++;
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.y > maxY) maxY = p.y;
          for (final d in [
            const math.Point(1, 0),
            const math.Point(-1, 0),
            const math.Point(0, 1),
            const math.Point(0, -1),
          ]) {
            final nx = p.x + d.x;
            final ny = p.y + d.y;
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            if (!mask[ny][nx] || labels[ny][nx] != 0) continue;
            labels[ny][nx] = nextLabel;
            queue.add(math.Point(nx, ny));
          }
        }
        components[nextLabel] = _Blob(
          count: count,
          cx: sumX / count,
          cy: sumY / count,
          width: maxX - minX + 1,
          height: maxY - minY + 1,
        );
        nextLabel++;
      }
    }

    final shots = <ShotImpact>[];
    for (final blob in components.values) {
      final radius = (blob.width + blob.height) / 4.0;
      if (radius < _minHoleRadiusCells) continue;
      if (radius > _maxHoleRadiusCells) continue;
      // Circularity gate: bullet holes are roughly round.
      final aspect = blob.width / (blob.height > 0 ? blob.height : 1);
      if (aspect < 0.35 || aspect > 2.8) continue;
      // Area/circumference circularity proxy: area vs bounding-circle area.
      final bboxArea = blob.width * blob.height;
      if (bboxArea <= 0) continue;
      final fill = blob.count / bboxArea;
      if (fill < 0.25) continue; // reject thin streaks / text strokes

      // Centroid back to full-resolution pixel coordinates.
      final px = Offset(
        (blob.cx * _sampleStep).clamp(0.0, w - 1.0),
        (blob.cy * _sampleStep).clamp(0.0, h - 1.0),
      );
      shots.add(ShotImpact(pixel: px, autoDetected: true));
    }

    // De-duplicate blobs whose centroids collapsed onto the same pixel.
    final deduped = <ShotImpact>[];
    for (final s in shots) {
      if (!deduped.any((e) => (e.pixel - s.pixel).distance < _sampleStep * 2)) {
        deduped.add(s);
      }
    }
    return deduped;
  }

  /// Compute the full group geometry from a set of shot points.
  ///
  /// [pxPerMm] is derived from a [ScaleReference] (0 if uncalibrated — the
  /// pixel-space metrics are still computed, angular metrics return 0).
  ShotGroupAnalysis analyze({
    required List<ShotImpact> shots,
    required double pxPerMm,
    required double distance,
    required DistanceUnit distanceUnit,
    Offset? aimPoint,
    AngularUnit angularUnit = AngularUnit.moa,
  }) {
    if (shots.isEmpty) {
      return ShotGroupAnalysis(
        shots: shots,
        pxPerMm: pxPerMm,
        distance: distance,
        distanceUnit: distanceUnit,
        aimPoint: aimPoint,
        centerOfImpactPx: Offset.zero,
        extremeSpreadPx: 0,
        extremeSpreadIndexA: -1,
        extremeSpreadIndexB: -1,
        meanRadiusPx: 0,
        extremeSpreadAngular: 0,
        meanRadiusAngular: 0,
        offsetHorizontalAngular: 0,
        offsetVerticalAngular: 0,
      );
    }

    // Center of impact = arithmetic centroid of all shot points.
    double sx = 0, sy = 0;
    for (final s in shots) {
      sx += s.x;
      sy += s.y;
    }
    final coi = Offset(sx / shots.length, sy / shots.length);

    // Extreme spread = max pairwise distance (record the pair).
    double maxDist = -1;
    int ia = 0, ib = 0;
    for (int i = 0; i < shots.length; i++) {
      for (int j = i + 1; j < shots.length; j++) {
        final d = (shots[i].pixel - shots[j].pixel).distance;
        if (d > maxDist) {
          maxDist = d;
          ia = i;
          ib = j;
        }
      }
    }

    // Mean radius = average distance of each shot from the COI.
    double radiusSum = 0;
    for (final s in shots) {
      radiusSum += (s.pixel - coi).distance;
    }
    final meanRadius = radiusSum / shots.length;

    // Angular conversions. 1 MOA = 1.047" at 100 yd (= 29.1mm at 100m).
    // 1 MIL = 3.6" at 100 yd (= 100mm at 100m).
    double lengthInches(double px) =>
        pxPerMm > 0 ? (px / pxPerMm) / 25.4 : 0.0;

    double toAngular(double px) {
      if (pxPerMm <= 0 || distance <= 0) return 0.0;
      final inches = lengthInches(px);
      return angularUnit == AngularUnit.moa
          ? inchesToMoa(inches, distance, distanceUnit)
          : inchesToMil(inches, distance, distanceUnit);
    }

    final esAngular = toAngular(maxDist);
    final mrAngular = toAngular(meanRadius);

    // COI offset from the aim point.
    double offHA = 0, offVA = 0;
    if (aimPoint != null) {
      final aim = aimPoint;
      final offRightIn = lengthInches((coi.dx - aim.dx).abs());
      final offUpIn = lengthInches((aim.dy - coi.dy).abs());
      offHA = (angularUnit == AngularUnit.moa
              ? inchesToMoa(offRightIn, distance, distanceUnit)
              : inchesToMil(offRightIn, distance, distanceUnit)) *
          (coi.dx >= aim.dx ? 1 : -1);
      offVA = (angularUnit == AngularUnit.moa
              ? inchesToMoa(offUpIn, distance, distanceUnit)
              : inchesToMil(offUpIn, distance, distanceUnit)) *
          (coi.dy <= aim.dy ? 1 : -1);
    }

    return ShotGroupAnalysis(
      shots: shots,
      pxPerMm: pxPerMm,
      distance: distance,
      distanceUnit: distanceUnit,
      aimPoint: aimPoint,
      centerOfImpactPx: coi,
      extremeSpreadPx: maxDist,
      extremeSpreadIndexA: ia,
      extremeSpreadIndexB: ib,
      meanRadiusPx: meanRadius,
      extremeSpreadAngular: esAngular,
      meanRadiusAngular: mrAngular,
      offsetHorizontalAngular: offHA,
      offsetVerticalAngular: offVA,
    );
  }

  // ---- Angular conversion helpers (physically exact) ----

  /// 1 MOA subtends 1.047" at 100 yards.
  static const double _moaInchesPer100Yd = 1.047;

  /// Convert a linear measurement in inches to MOA at [distance].
  static double inchesToMoa(double inches, double distance, DistanceUnit unit) {
    // Express the target distance in yards (1 m = 1.0936 yd).
    final yards = unit == DistanceUnit.yards ? distance : distance * 1.0936;
    if (yards <= 0) return 0.0;
    return inches / (_moaInchesPer100Yd * yards / 100.0);
  }

  /// Convert a linear measurement in inches to MIL at [distance].
  /// 1 MIL = 3.6" at 100 yards (= 100mm at 100m).
  static double inchesToMil(double inches, double distance, DistanceUnit unit) {
    final yards = unit == DistanceUnit.yards ? distance : distance * 1.0936;
    if (yards <= 0) return 0.0;
    return inches / (3.6 * yards / 100.0);
  }

  static double milToMoa(double mil) => mil * 3.6 / _moaInchesPer100Yd;

  /// Suggested turret correction (clicks) to move the COI onto the aim point.
  /// [clickValue] is the scope's per-click angular value in the same unit as
  /// [unit] (e.g. 0.25 for a 1/4-MOA scope, 0.1 for a 0.1-MIL scope).
  ({int upClicks, int rightClicks}) suggestedClicks(
    ShotGroupAnalysis analysis,
    AngularUnit unit,
    double clickValue,
  ) {
    if (analysis.aimPoint == null || clickValue <= 0) {
      return (upClicks: 0, rightClicks: 0);
    }
    // The shooter dials opposite to the COI offset: COI right → dial left,
    // COI low → dial up. Express the offset in [unit] first.
    final moaUnit = unit;
    final offH = analysis.offsetHorizontalAngular == 0
        ? _convert(analysis.offsetHorizontalMm, analysis, moaUnit, isHorizontal: true)
        : analysis.offsetHorizontalAngular;
    final offV = analysis.offsetVerticalAngular == 0
        ? _convert(analysis.offsetVerticalMm, analysis, moaUnit, isHorizontal: false)
        : analysis.offsetVerticalAngular;
    return (
      // COI is low (negative offV) → dial UP (positive); COI high → dial down.
      upClicks: (-offV / clickValue).round(),
      // COI is right (+) → dial left (−). Magnitude-neutral sign per axis.
      rightClicks: (-offH / clickValue).round(),
    );
  }

  // Helper to reconvert an mm offset to angular when the analysis was
  // uncalibrated at build time (kept for completeness; normally the angular
  // fields are populated directly).
  static double _convert(
      double mm, ShotGroupAnalysis a, AngularUnit unit, {required bool isHorizontal}) {
    final inches = mm / 25.4;
    return unit == AngularUnit.moa
        ? inchesToMoa(inches, a.distance, a.distanceUnit)
        : inchesToMil(inches, a.distance, a.distanceUnit);
  }
}

class _Blob {
  final int count;
  final double cx;
  final double cy;
  final int width;
  final int height;
  const _Blob({
    required this.count,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
  });
}
