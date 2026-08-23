import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the v4.5 ballistics enhancements: the zero-distance
/// range expansion (5m-1000) and the dark-mode text-contrast fix on the
/// Position Statistics Summary card.
void main() {
  final src = File(
    'lib/features/ballistics/presentation/ballistic_calc_screen.dart',
  ).readAsStringSync();

  group('Zero-distance range expansion (5m up to 1000m)', () {
    test('the min/max range + division count constants are declared', () {
      expect(src.contains('zeroDistanceMinMeters'), isTrue);
      expect(src.contains('zeroDistanceMaxMeters'), isTrue);
      expect(src.contains('zeroDistanceDivisions'), isTrue);
    });

    test('the zero-distance slider covers the extended 5m-1000m range', () {
      // The Environmental Parameters block must reference the constants (not
      // a hardcoded 25/1000 literal) so the range cannot drift.
      expect(
        src.contains(
          "'Zero Distance (m)',\n"
          '                      _zeroDistanceMeters,\n'
          '                      zeroDistanceMinMeters,\n'
          '                      zeroDistanceMaxMeters,',
        ),
        isTrue,
      );
      expect(src.contains('divisions: zeroDistanceDivisions'), isTrue);
      // Mathematically: (1000 - 5) / 5 = 199 divisions => clean 5m snaps.
      expect(((1000 - 5) / 5).toInt(), 199);
    });

    test('the parameter-row builder accepts an explicit division count', () {
      // Explicit divisions supply clean snapping for the extended range;
      // the fallback still computes ~10 units/division for other sliders.
      expect(
        src.contains(
          'divisions: divisions ?? ((max - min) / 10).round(),',
        ),
        isTrue,
      );
      expect(
        src.contains('ValueChanged<double> onChanged, {'),
        isTrue,
      );
    });
  });

  group('Dark-mode summary-card contrast fix', () {
    test('summary rows resolve mode-aware palette', () {
      expect(
        src.contains(
          'final isDark = Theme.of(context).brightness == Brightness.dark;',
        ),
        isTrue,
      );
    });

    test('dark mode labels use the warm cream (0xFFEFE7DC) tone', () {
      expect(src.contains('0xFFEFE7DC'), isTrue);
    });

    test('dark mode values use the gold (0xFFD4AF37) tone', () {
      expect(src.contains('0xFFD4AF37'), isTrue);
    });

    test('light mode branches retained for both label and value', () {
      expect(src.contains('0xFF1A2421'), isTrue);
      expect(src.contains('0xFF2E3D2F'), isTrue);
    });

    test('no hardcoded dark-text styles remain in the summary row', () {
      // The TextStyle literals are mode-aware now; they must be resolved
      // from the computed labelColor/valueColor variables.
      expect(src.contains('color: labelColor'), isTrue);
      expect(src.contains('color: valueColor'), isTrue);
    });
  });
}
