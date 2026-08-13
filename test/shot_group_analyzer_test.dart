import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jagspoor/features/hunter_mode/services/shot_group_analyzer_service.dart';

void main() {
  final svc = ShotGroupAnalyzerService.instance;

  group('ShotGroupAnalyzerService math', () {
    test('center of impact is the arithmetic centroid of the shots', () {
      final shots = [
        ShotImpact(pixel: Offset(0, 0)),
        ShotImpact(pixel: Offset(10, 0)),
        ShotImpact(pixel: Offset(0, 10)),
        ShotImpact(pixel: Offset(10, 10)),
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0, // 1px = 1mm
        distance: 100,
        distanceUnit: DistanceUnit.yards,
      );
      expect(a.centerOfImpactPx, Offset(5, 5));
    });

    test('extreme spread is the largest pairwise distance', () {
      final shots = [
        ShotImpact(pixel: Offset(0, 0)),
        ShotImpact(pixel: Offset(0, 30)), // 30px
        ShotImpact(pixel: Offset(40, 0)), // 40px from shot0, 50px from shot1
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
      );
      // 50px between shot1(0,30) and shot2(40,0) = 50mm = 1.9685"
      expect(a.extremeSpreadPx, closeTo(50.0, 1e-6));
      expect(a.extremeSpreadIndexA, 1);
      expect(a.extremeSpreadIndexB, 2);
      expect(a.extremeSpreadMm, closeTo(50.0, 1e-9));
      // 1.9685" at 100yd → /1.047 = 1.88 MOA
      expect(a.extremeSpreadAngular, closeTo(1.88, 0.01));
    });

    test('mean radius averages each shot distance from the COI', () {
      final shots = [
        ShotImpact(pixel: Offset(0, 0)),
        ShotImpact(pixel: Offset(10, 0)),
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
      );
      // COI = (5,0); each shot 5mm from COI → mean radius 5mm.
      expect(a.meanRadiusPx, closeTo(5.0, 1e-9));
      expect(a.meanRadiusMm, closeTo(5.0, 1e-9));
    });

    test('MOA conversion matches the 1.047" per 100yd definition', () {
      // 1.047" at 100yd == exactly 1 MOA.
      final moa = ShotGroupAnalyzerService.inchesToMoa(1.047, 100, DistanceUnit.yards);
      expect(moa, closeTo(1.0, 1e-3));
      // Double distance → half the angular size.
      final moa200 = ShotGroupAnalyzerService.inchesToMoa(1.047, 200, DistanceUnit.yards);
      expect(moa200, closeTo(0.5, 1e-3));
    });

    test('MIL conversion matches the 3.6" per 100yd definition', () {
      // 3.6" at 100yd == exactly 1 MIL.
      final mil = ShotGroupAnalyzerService.inchesToMil(3.6, 100, DistanceUnit.yards);
      expect(mil, closeTo(1.0, 1e-3));
      // 100mm at 100m ≈ 1 MIL (100m = 109.36yd, 3.937", / (3.6*1.0936) ≈ 1.0).
      final milM = ShotGroupAnalyzerService.inchesToMil(
          3.937, 100, DistanceUnit.meters);
      expect(milM, closeTo(1.0, 1e-2));
    });

    test('meters distance converts correctly to MOA', () {
      // 29.1mm = ~1.146" at 100m ≈ 1 MOA (1.047" * 100/109.36 yd ... ~1 MOA).
      final shots = [ShotImpact(pixel: Offset(0, 0)), ShotImpact(pixel: Offset(29.1, 0))];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.meters,
        angularUnit: AngularUnit.moa,
      );
      expect(a.extremeSpreadAngular, closeTo(1.0, 0.02));
    });

    test('center of impact offset is measured from the marked aim point', () {
      // Aim at origin; shots land 10px right & 10px down (image y down).
      final shots = [
        ShotImpact(pixel: Offset(20, 0)),
        ShotImpact(pixel: Offset(0, 20)),
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        aimPoint: Offset(0, 0),
        angularUnit: AngularUnit.moa,
      );
      // COI = (10,10): image y grows down, so COI is 10mm right and 10mm LOW
      // (below the aim point). Positive vertical = up, so a low COI is negative.
      expect(a.offsetHorizontalMm, closeTo(10.0, 1e-9));
      expect(a.offsetVerticalMm, closeTo(-10.0, 1e-9));
    });

    test('uncalibrated analysis returns zero angular metrics but valid px', () {
      final shots = [
        ShotImpact(pixel: Offset(0, 0)),
        ShotImpact(pixel: Offset(50, 0)),
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 0, // uncalibrated
        distance: 100,
        distanceUnit: DistanceUnit.yards,
      );
      expect(a.isCalibrated, isFalse);
      expect(a.extremeSpreadPx, closeTo(50.0, 1e-9));
      expect(a.extremeSpreadMm, 0.0);
      expect(a.extremeSpreadAngular, 0.0);
    });

    test('empty shot list yields a zeroed analysis', () {
      final a = svc.analyze(
        shots: const [],
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
      );
      expect(a.shots, isEmpty);
      expect(a.extremeSpreadPx, 0);
      expect(a.meanRadiusPx, 0);
      expect(a.extremeSpreadIndexA, -1);
    });

    test('precisionCategory thresholds map MIL back to MOA', () {
      // ~0.5 MIL ≈ 1.72 MOA → 'Average Group'.
      final shots = [
        ShotImpact(pixel: Offset(0, 0)),
        ShotImpact(pixel: Offset(60, 0)),
      ];
      final a = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.mil,
      );
      // 60mm = 2.362" at 100yd → 0.655 MIL ≈ 2.24 MOA → Open Group (>2)
      // Recompute precisely: 2.362/3.6 = 0.656 MIL → 2.24 MOA → 'Open Group'
      expect(a.precisionCategory(AngularUnit.mil), 'Open Group');
    });

    test('detectShotHoles finds dark round blobs and rejects noise', () {
      // Use the image package to build a synthetic target.
      final image = _buildTargetImageWithHoles();
      final detected = svc.detectShotHoles(image);
      // 3 distinct shot holes should be found; no false positives from dust.
      expect(detected.length, 3);
      for (final s in detected) {
        expect(s.autoDetected, isTrue);
      }
    });
  });
}

/// Builds a synthetic light target with 3 dark round shot holes + a few tiny
/// dark dust specks that the detector must reject (too small).
img.Image _buildTargetImageWithHoles() {
  const size = 400;
  final image = img.Image(width: size, height: size);
  // Light target-paper background.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, 235, 235, 225);
    }
  }
  // Three dark round shot holes (radius ~12px).
  _disc(image, 100, 100, 12);
  _disc(image, 220, 140, 12);
  _disc(image, 160, 260, 12);
  // Dust specks (radius ~1px) — below the min-hole radius gate.
  _disc(image, 50, 50, 1);
  _disc(image, 350, 350, 1);
  return image;
}

void _disc(img.Image image, int cx, int cy, int r) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
        image.setPixelRgb(x, y, 25, 25, 25);
      }
    }
  }
}
