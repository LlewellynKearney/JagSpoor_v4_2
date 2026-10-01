import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'track_taxonomy.dart';

/// Morphological spoor attributes for a species, used by the structured
/// validation layer to cross-check raw camera classifications.
///
/// The attributes are the discriminators a tracker uses on the ground:
/// * [toeCount] — the canonical number of toes/cleaves (4 for a felid paw,
///   including the four main toes; 2 for a cloven-hoofed ungulate; 1 for a
///   solid-hoofed equine).
/// * [lengthMinMm] / [lengthMaxMm] — expected print-length range.
/// * [widthMinMm] / [widthMaxMm] — expected print-width range.
///
/// Attributes may be hydrated from a Firestore `animals` document (so admins
/// can refine them without a code change) or from the built-in fallback
/// table when the database has no record / is unreachable. They may also be
/// *measured* directly from a captured frame via [fromXFile], in which case
/// the contour fields ([widthPx], [heightPx], [contourAreaPx],
/// [contourPerimeterPx]) drive the [circularity] / [aspectRatio] getters the
/// validation layer consumes.
class SpoorTrackAttributes {
  final String species;
  final int toeCount;
  final double lengthMinMm;
  final double lengthMaxMm;
  final double widthMinMm;
  final double widthMaxMm;
  final TrackCategory category;

  /// Measured contour geometry in image pixels (0 when the attributes were
  /// hydrated from a species record rather than measured from a frame).
  final double widthPx;
  final double heightPx;
  final double contourAreaPx;
  final double contourPerimeterPx;

  /// Toe/cleave count resolved from the measured contour lobes (0 = unknown).
  final int estimatedToeCount;

  /// The scale-reference length used to calibrate pixel → millimetre, when one
  /// was supplied at measurement time.
  final double? scaleReferenceMm;

  const SpoorTrackAttributes({
    required this.species,
    required this.toeCount,
    required this.lengthMinMm,
    required this.lengthMaxMm,
    required this.widthMinMm,
    required this.widthMaxMm,
    this.category = TrackCategory.clovenHoofUngulate,
    this.widthPx = 0,
    this.heightPx = 0,
    this.contourAreaPx = 0,
    this.contourPerimeterPx = 0,
    this.estimatedToeCount = 0,
    this.scaleReferenceMm,
  });

  /// Whether a usable dark-pixel contour was extracted from the frame.
  ///
  /// The validation layer treats a `false` here as "no opinion" and keeps the
  /// raw AI ranking untouched.
  bool get hasUsableContour =>
      contourAreaPx > 0 && contourPerimeterPx > 0 && widthPx > 0 && heightPx > 0;

  /// Contour circularity: 4π·area / perimeter² (1.0 = a perfect circle).
  /// Returns 0 when no usable contour was measured.
  double get circularity {
    if (contourPerimeterPx <= 0 || contourAreaPx <= 0) return 0.0;
    final value = 4.0 *
        math.pi *
        contourAreaPx /
        (contourPerimeterPx * contourPerimeterPx);
    return value.clamp(0.0, 1.0);
  }

  /// Bounding-box aspect ratio: height ÷ width (≈1.0 for a round felid paw,
  /// >1.3 for an elongated hoof). Returns 0 when no contour was measured.
  double get aspectRatio {
    if (widthPx <= 0 || heightPx <= 0) return 0.0;
    return heightPx / widthPx;
  }

  /// Measures the track geometry from a captured camera frame.
  ///
  /// The image is decoded, thresholded (Otsu — adaptive to the scene
  /// lighting), reduced to its largest connected dark component (so soil
  /// speckle / shadows are rejected) and reduced to its contour area +
  /// perimeter. The returned attributes carry the measured [widthPx] /
  /// [heightPx] / [contourAreaPx] / [contourPerimeterPx] plus the
  /// [estimatedToeCount], and the calibrated print dimensions when a
  /// [scaleReferenceMm] is supplied.
  ///
  /// Never throws: an undecodable frame yields an unusable (all-zero) contour
  /// so the validation layer stays neutral.
  static Future<SpoorTrackAttributes> fromXFile(
    XFile file, {
    double? scaleReferenceMm,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return _unusable(scaleReferenceMm: scaleReferenceMm);
      }
      return _measure(decoded, scaleReferenceMm: scaleReferenceMm);
    } catch (_) {
      return _unusable(scaleReferenceMm: scaleReferenceMm);
    }
  }

  /// Builds an unusable (all-zero contour) attribute set — the neutral input
  /// the validation layer interprets as "no morphology opinion".
  static SpoorTrackAttributes _unusable({double? scaleReferenceMm}) =>
      SpoorTrackAttributes(
        species: '',
        toeCount: 0,
        lengthMinMm: 0,
        lengthMaxMm: 0,
        widthMinMm: 0,
        widthMaxMm: 0,
        scaleReferenceMm: scaleReferenceMm,
      );

  static SpoorTrackAttributes _measure(
    img.Image image, {
    double? scaleReferenceMm,
  }) {
    const sampleStep = 4;
    final imgWidth = image.width;
    final imgHeight = image.height;
    final threshold = _otsuThreshold(image);

    final grid = <List<bool>>[];
    for (int y = 0; y < imgHeight; y += sampleStep) {
      final row = <bool>[];
      for (int x = 0; x < imgWidth; x += sampleStep) {
        row.add(_luminanceAt(image, x, y) < threshold);
      }
      grid.add(row);
    }

    final gridW = grid.isNotEmpty ? grid.first.length : 0;
    final gridH = grid.length;
    final keepMask = _largestComponentMask(grid, gridW, gridH);

    int minX = imgWidth, maxX = 0, minY = imgHeight, maxY = 0;
    int area = 0;
    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        if (!keepMask[gy][gx]) continue;
        final x = gx * sampleStep;
        final y = gy * sampleStep;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        area++;
      }
    }

    if (area == 0) return _unusable(scaleReferenceMm: scaleReferenceMm);

    int perimeter = 0;
    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        if (!keepMask[gy][gx]) continue;
        final left = gx == 0 ? false : keepMask[gy][gx - 1];
        final right = gx == gridW - 1 ? false : keepMask[gy][gx + 1];
        final up = gy == 0 ? false : keepMask[gy - 1][gx];
        final down = gy == gridH - 1 ? false : keepMask[gy + 1][gx];
        if (!left || !right || !up || !down) perimeter++;
      }
    }

    final widthPx = (maxX > minX ? (maxX - minX) : 0).toDouble();
    final heightPx = (maxY > minY ? (maxY - minY) : 0).toDouble();
    final contourPerimeterPx = perimeter * sampleStep.toDouble();
    final contourAreaPx = area * (sampleStep * sampleStep);

    final estimatedToeCount =
        area > 12 ? _estimateToeLobes(keepMask, gridW, gridH) : 0;

    // Pixel → millimetre calibration: a scale reference spanning the frame
    // width, else the legacy focal-scaling constant.
    final pxPerMm = (scaleReferenceMm != null && scaleReferenceMm > 0)
        ? imgWidth / scaleReferenceMm
        : 1.0 / 0.475;
    final printWidthMm = (widthPx / pxPerMm).clamp(20.0, 300.0);
    final printLengthMm = (heightPx / pxPerMm).clamp(20.0, 300.0);

    return SpoorTrackAttributes(
      species: '',
      toeCount: estimatedToeCount,
      lengthMinMm: printLengthMm,
      lengthMaxMm: printLengthMm,
      widthMinMm: printWidthMm,
      widthMaxMm: printWidthMm,
      widthPx: widthPx,
      heightPx: heightPx,
      contourAreaPx: contourAreaPx.toDouble(),
      contourPerimeterPx: contourPerimeterPx,
      estimatedToeCount: estimatedToeCount,
      scaleReferenceMm: scaleReferenceMm,
    );
  }

  /// Otsu's method: the luminance cut maximising between-class variance, so
  /// the track/background split adapts to the actual scene illumination
  /// (bright sand vs dark muddy soil) instead of a fixed threshold.
  static int _otsuThreshold(img.Image image) {
    const sampleStep = 4;
    final histogram = List<int>.filled(256, 0);
    int total = 0;
    for (int y = 0; y < image.height; y += sampleStep) {
      for (int x = 0; x < image.width; x += sampleStep) {
        final lum = _luminanceAt(image, x, y).round().clamp(0, 255);
        histogram[lum]++;
        total++;
      }
    }
    if (total == 0) return 140;

    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }

    double sumB = 0;
    int weightB = 0;
    double maxVariance = -1;
    int threshold = 140;
    for (int t = 0; t < 256; t++) {
      weightB += histogram[t];
      if (weightB == 0) continue;
      final weightF = total - weightB;
      if (weightF == 0) break;
      sumB += t * histogram[t];
      final meanB = sumB / weightB;
      final meanF = (sumAll - sumB) / weightF;
      final variance = weightB * weightF * (meanB - meanF) * (meanB - meanF);
      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = t;
      }
    }
    return threshold;
  }

  static double _luminanceAt(img.Image image, int x, int y) {
    final pixel = image.getPixelSafe(x, y);
    return 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
  }

  /// Flood-fills the sampled grid and returns the mask of the largest
  /// 4-connected dark component (soil speckle / shadows are discarded).
  static List<List<bool>> _largestComponentMask(
    List<List<bool>> grid,
    int gridW,
    int gridH,
  ) {
    final visited = List.generate(gridH, (_) => List<bool>.filled(gridW, false));
    var bestMask = List.generate(gridH, (_) => List<bool>.filled(gridW, false));
    int bestSize = 0;

    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        if (visited[gy][gx] || !grid[gy][gx]) continue;
        final component = <List<int>>[];
        final stack = <List<int>>[
          [gx, gy],
        ];
        visited[gy][gx] = true;
        while (stack.isNotEmpty) {
          final cell = stack.removeLast();
          component.add(cell);
          final cx = cell[0], cy = cell[1];
          void push(int nx, int ny) {
            if (nx < 0 || ny < 0 || nx >= gridW || ny >= gridH) return;
            if (visited[ny][nx] || !grid[ny][nx]) return;
            visited[ny][nx] = true;
            stack.add([nx, ny]);
          }

          push(cx - 1, cy);
          push(cx + 1, cy);
          push(cx, cy - 1);
          push(cx, cy + 1);
        }
        if (component.length > bestSize) {
          bestSize = component.length;
          final mask =
              List.generate(gridH, (_) => List<bool>.filled(gridW, false));
          for (final cell in component) {
            mask[cell[1]][cell[0]] = true;
          }
          bestMask = mask;
        }
      }
    }
    return bestMask;
  }

  /// Estimates the toe/cleave count from the number of distinct dark lobes
  /// projected onto the track's horizontal axis (a 2-cleaved hoof shows two
  /// lobes, a 1-wall equine one broad lobe, a 4-toed paw up to four).
  static int _estimateToeLobes(
    List<List<bool>> mask,
    int gridW,
    int gridH,
  ) {
    final columnCounts = List<int>.filled(gridW, 0);
    for (int gx = 0; gx < gridW; gx++) {
      for (int gy = 0; gy < gridH; gy++) {
        if (mask[gy][gx]) columnCounts[gx]++;
      }
    }
    final maxCount =
        columnCounts.fold<int>(0, (m, c) => c > m ? c : m);
    if (maxCount == 0) return 0;

    // Count contiguous runs of "populated" columns above a noise floor.
    final floor = math.max(1, (maxCount * 0.25).round());
    int lobes = 0;
    bool inLobe = false;
    for (final count in columnCounts) {
      if (count >= floor) {
        if (!inLobe) {
          lobes++;
          inLobe = true;
        }
      } else {
        inLobe = false;
      }
    }
    return lobes.clamp(0, 4);
  }

  /// Hydrates attributes from a Firestore `animals` document map.
  ///
  /// Numeric strings are tolerated; a missing/invalid field falls back to
  /// [fallback] (typically the built-in table) so a partial document never
  /// yields a null/empty attribute set.
  factory SpoorTrackAttributes.fromMap(
    Map<String, dynamic> data, {
    required String species,
    SpoorTrackAttributes? fallback,
  }) {
    final fb = fallback ?? spoorTrackAttributesFallback[species];
    final toe = _intOrNull(
      data['toeCount'] ??
          data['toe_count'] ??
          data['hoofCount'] ??
          data['pawToes'],
    );
    final lenMin = _doubleOrNull(
      data['trackLengthMinMm'] ??
          data['track_length_min_mm'] ??
          data['printLengthMinMm'],
    );
    final lenMax = _doubleOrNull(
      data['trackLengthMaxMm'] ??
          data['track_length_max_mm'] ??
          data['printLengthMaxMm'],
    );
    final widMin = _doubleOrNull(
      data['trackWidthMinMm'] ??
          data['track_width_min_mm'] ??
          data['printWidthMinMm'],
    );
    final widMax = _doubleOrNull(
      data['trackWidthMaxMm'] ??
          data['track_width_max_mm'] ??
          data['printWidthMaxMm'],
    );

    final resolvedToe = toe ?? ((fb != null) ? fb.toeCount : 0);
    final resolvedLenMin = lenMin ?? ((fb != null) ? fb.lengthMinMm : 0);
    final resolvedLenMax =
        lenMax ?? ((fb != null) ? fb.lengthMaxMm : resolvedLenMin);
    final resolvedWidMin = widMin ?? ((fb != null) ? fb.widthMinMm : 0);
    final resolvedWidMax =
        widMax ?? ((fb != null) ? fb.widthMaxMm : resolvedWidMin);
    final resolvedCategory =
        (fb != null) ? fb.category : categoryForSpecies(species);

    return SpoorTrackAttributes(
      species: species,
      toeCount: resolvedToe,
      lengthMinMm: resolvedLenMin,
      lengthMaxMm: resolvedLenMax,
      widthMinMm: resolvedWidMin,
      widthMaxMm: resolvedWidMax,
      category: resolvedCategory,
    );
  }

  /// Whether the geometry is compatible with these attributes.
  ///
  /// A candidate passes when BOTH the estimated toe count matches (when the
  /// count could be estimated) AND the calibrated print length/width fall
  /// within the species' expected ranges (tolerating a small overlap slack).
  bool matches({
    required int? estimatedToeCount,
    required double? printLengthMm,
    required double? printWidthMm,
    double slackMm = 8.0,
    bool requireToeCount = true,
  }) {
    if (requireToeCount &&
        estimatedToeCount != null &&
        estimatedToeCount > 0 &&
        toeCount > 0 &&
        estimatedToeCount != toeCount) {
      return false;
    }
    if (printLengthMm != null && lengthMaxMm > 0) {
      final lenMargin = (lengthMaxMm - lengthMinMm).abs() + slackMm;
      if (printLengthMm < lengthMinMm - slackMm ||
          printLengthMm > lengthMaxMm + slackMm) {
        // Allow a generous catch-all for unidentified/median species when the
        // DB range is very tight and the observation is close.
        if (lenMargin > 0 &&
            (printLengthMm - lengthMinMm).abs() > lenMargin * 1.5) {
          return false;
        }
      }
    }
    if (printWidthMm != null && widthMaxMm > 0) {
      final widMargin = (widthMaxMm - widthMinMm).abs() + slackMm;
      if (printWidthMm < widthMinMm - slackMm ||
          printWidthMm > widthMaxMm + slackMm) {
        if (widMargin > 0 &&
            (printWidthMm - widthMinMm).abs() > widMargin * 1.5) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  String toString() =>
      '$species (toes: $toeCount, L: ${lengthMinMm.toStringAsFixed(0)}–${lengthMaxMm.toStringAsFixed(0)} mm, '
      'W: ${widthMinMm.toStringAsFixed(0)}–${widthMaxMm.toStringAsFixed(0)} mm)';

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Whether the DB hydration actually supplied any spoor field.
  static bool anySpoorFieldPresent(Map<String, dynamic> data) {
    return data.containsKey('toeCount') ||
        data.containsKey('toe_count') ||
        data.containsKey('hoofCount') ||
        data.containsKey('trackLengthMinMm') ||
        data.containsKey('track_length_min_mm') ||
        data.containsKey('trackWidthMaxMm') ||
        data.containsKey('track_width_max_mm');
  }
}

/// Built-in fallback spoor attributes keyed by canonical species name.
///
/// This doubles as the offline baseline when the Firestore `animals`
/// collection is unreachable or a species has no stored record. Dimensions
/// are mature-field averages; ranges widen with the observed variance.
const Map<String, SpoorTrackAttributes> spoorTrackAttributesFallback = {
  // Felid / carnivore paws — 4 toes + a three-lobed heel pad.
  'Leopard': SpoorTrackAttributes(
    species: 'Leopard',
    toeCount: 4,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 80,
    widthMaxMm: 100,
    category: TrackCategory.pawCarnivore,
  ),
  'Lion': SpoorTrackAttributes(
    species: 'Lion',
    toeCount: 4,
    lengthMinMm: 120,
    lengthMaxMm: 150,
    widthMinMm: 110,
    widthMaxMm: 140,
    category: TrackCategory.pawCarnivore,
  ),
  'Cheetah': SpoorTrackAttributes(
    species: 'Cheetah',
    toeCount: 4,
    lengthMinMm: 72,
    lengthMaxMm: 92,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.pawCarnivore,
  ),
  'Caracal': SpoorTrackAttributes(
    species: 'Caracal',
    toeCount: 4,
    lengthMinMm: 48,
    lengthMaxMm: 68,
    widthMinMm: 42,
    widthMaxMm: 62,
    category: TrackCategory.pawCarnivore,
  ),
  'Wild Cat': SpoorTrackAttributes(
    species: 'Wild Cat',
    toeCount: 4,
    lengthMinMm: 30,
    lengthMaxMm: 46,
    widthMinMm: 26,
    widthMaxMm: 42,
    category: TrackCategory.pawCarnivore,
  ),
  'Wildcat': SpoorTrackAttributes(
    species: 'Wildcat',
    toeCount: 4,
    lengthMinMm: 30,
    lengthMaxMm: 46,
    widthMinMm: 26,
    widthMaxMm: 42,
    category: TrackCategory.pawCarnivore,
  ),
  'Hyena': SpoorTrackAttributes(
    species: 'Hyena',
    toeCount: 4,
    lengthMinMm: 95,
    lengthMaxMm: 125,
    widthMinMm: 80,
    widthMaxMm: 105,
    category: TrackCategory.pawCarnivore,
  ),
  'Jackal': SpoorTrackAttributes(
    species: 'Jackal',
    toeCount: 4,
    lengthMinMm: 55,
    lengthMaxMm: 70,
    widthMinMm: 40,
    widthMaxMm: 52,
    category: TrackCategory.pawCarnivore,
  ),
  'Serval': SpoorTrackAttributes(
    species: 'Serval',
    toeCount: 4,
    lengthMinMm: 45,
    lengthMaxMm: 60,
    widthMinMm: 38,
    widthMaxMm: 50,
    category: TrackCategory.pawCarnivore,
  ),

  // Cloven-hoofed ungulates — 2 cleaves.
  'Kudu': SpoorTrackAttributes(
    species: 'Kudu',
    toeCount: 2,
    lengthMinMm: 75,
    lengthMaxMm: 105,
    widthMinMm: 50,
    widthMaxMm: 70,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Cape Buffalo': SpoorTrackAttributes(
    species: 'Cape Buffalo',
    toeCount: 2,
    lengthMinMm: 130,
    lengthMaxMm: 170,
    widthMinMm: 120,
    widthMaxMm: 160,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Buffalo': SpoorTrackAttributes(
    species: 'Buffalo',
    toeCount: 2,
    lengthMinMm: 130,
    lengthMaxMm: 170,
    widthMinMm: 120,
    widthMaxMm: 160,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Impala': SpoorTrackAttributes(
    species: 'Impala',
    toeCount: 2,
    lengthMinMm: 45,
    lengthMaxMm: 62,
    widthMinMm: 30,
    widthMaxMm: 42,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Gemsbok': SpoorTrackAttributes(
    species: 'Gemsbok',
    toeCount: 2,
    lengthMinMm: 72,
    lengthMaxMm: 95,
    widthMinMm: 48,
    widthMaxMm: 68,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Eland': SpoorTrackAttributes(
    species: 'Eland',
    toeCount: 2,
    lengthMinMm: 115,
    lengthMaxMm: 145,
    widthMinMm: 88,
    widthMaxMm: 112,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Warthog': SpoorTrackAttributes(
    species: 'Warthog',
    toeCount: 2,
    lengthMinMm: 58,
    lengthMaxMm: 80,
    widthMinMm: 40,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Nyala': SpoorTrackAttributes(
    species: 'Nyala',
    toeCount: 2,
    lengthMinMm: 70,
    lengthMaxMm: 88,
    widthMinMm: 45,
    widthMaxMm: 60,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Springbok': SpoorTrackAttributes(
    species: 'Springbok',
    toeCount: 2,
    lengthMinMm: 40,
    lengthMaxMm: 55,
    widthMinMm: 26,
    widthMaxMm: 36,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Blesbok': SpoorTrackAttributes(
    species: 'Blesbok',
    toeCount: 2,
    lengthMinMm: 50,
    lengthMaxMm: 62,
    widthMinMm: 32,
    widthMaxMm: 42,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Hartebeest': SpoorTrackAttributes(
    species: 'Hartebeest',
    toeCount: 2,
    lengthMinMm: 78,
    lengthMaxMm: 90,
    widthMinMm: 48,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Red Hartebeest': SpoorTrackAttributes(
    species: 'Red Hartebeest',
    toeCount: 2,
    lengthMinMm: 78,
    lengthMaxMm: 90,
    widthMinMm: 48,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Wildebeest': SpoorTrackAttributes(
    species: 'Wildebeest',
    toeCount: 2,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Blue Wildebeest': SpoorTrackAttributes(
    species: 'Blue Wildebeest',
    toeCount: 2,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Roan Antelope': SpoorTrackAttributes(
    species: 'Roan Antelope',
    toeCount: 2,
    lengthMinMm: 95,
    lengthMaxMm: 115,
    widthMinMm: 65,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Sable Antelope': SpoorTrackAttributes(
    species: 'Sable Antelope',
    toeCount: 2,
    lengthMinMm: 88,
    lengthMaxMm: 108,
    widthMinMm: 55,
    widthMaxMm: 70,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Bushbuck': SpoorTrackAttributes(
    species: 'Bushbuck',
    toeCount: 2,
    lengthMinMm: 55,
    lengthMaxMm: 68,
    widthMinMm: 36,
    widthMaxMm: 46,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Duiker': SpoorTrackAttributes(
    species: 'Duiker',
    toeCount: 2,
    lengthMinMm: 30,
    lengthMaxMm: 42,
    widthMinMm: 18,
    widthMaxMm: 28,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Steenbok': SpoorTrackAttributes(
    species: 'Steenbok',
    toeCount: 2,
    lengthMinMm: 28,
    lengthMaxMm: 38,
    widthMinMm: 16,
    widthMaxMm: 24,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Oribi': SpoorTrackAttributes(
    species: 'Oribi',
    toeCount: 2,
    lengthMinMm: 30,
    lengthMaxMm: 40,
    widthMinMm: 18,
    widthMaxMm: 26,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Giraffe': SpoorTrackAttributes(
    species: 'Giraffe',
    toeCount: 2,
    lengthMinMm: 160,
    lengthMaxMm: 220,
    widthMinMm: 120,
    widthMaxMm: 170,
    category: TrackCategory.clovenHoofUngulate,
  ),

  // Solid-hoofed equines — 1 hoof wall.
  'Zebra': SpoorTrackAttributes(
    species: 'Zebra',
    toeCount: 1,
    lengthMinMm: 95,
    lengthMaxMm: 125,
    widthMinMm: 85,
    widthMaxMm: 115,
    category: TrackCategory.solidHoofEquine,
  ),
  'Donkey': SpoorTrackAttributes(
    species: 'Donkey',
    toeCount: 1,
    lengthMinMm: 80,
    lengthMaxMm: 105,
    widthMinMm: 70,
    widthMaxMm: 95,
    category: TrackCategory.solidHoofEquine,
  ),
  'Horse': SpoorTrackAttributes(
    species: 'Horse',
    toeCount: 1,
    lengthMinMm: 105,
    lengthMaxMm: 135,
    widthMinMm: 90,
    widthMaxMm: 115,
    category: TrackCategory.solidHoofEquine,
  ),
};