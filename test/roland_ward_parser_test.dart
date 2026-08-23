import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/utils/animal_seeder.dart';

/// The Field Estimate Verification screen previously mangled mixed-fraction
/// Roland Ward minimums (e.g. "22 7/8 inches" -> 2278), so a 30.00-inch
/// estimate was reported as below-minimum. These tests lock the shared
/// fraction-aware parser + the `estimate >= minimum` qualification logic.
void main() {
  group('parseRolandWardMinimumValue', () {
    test('parses mixed fractions (22 7/8 inches -> 22.875)', () {
      expect(parseRolandWardMinimumValue('22 7/8 inches'), closeTo(22.875, 0.0001));
    });

    test('parses mixed fractions with long numerals', () {
      expect(
          parseRolandWardMinimumValue('53 7/8 inches'), closeTo(53.875, 0.0001));
      expect(parseRolandWardMinimumValue('41 7/8 inches'), closeTo(41.875, 0.0001));
    });

    test('parses simple fractions', () {
      expect(parseRolandWardMinimumValue('7/8'), closeTo(0.875, 0.0001));
    });

    test('parses whole numbers with suffixes', () {
      expect(parseRolandWardMinimumValue('35 inches'), 35.0);
      expect(parseRolandWardMinimumValue('40 inches'), 40.0);
      expect(parseRolandWardMinimumValue('42'), 42.0);
    });

    test('parses decimals', () {
      expect(parseRolandWardMinimumValue('27.5 inches'), 27.5);
    });

    test('parses compact half-inch denominators', () {
      expect(parseRolandWardMinimumValue('28 1/2 inches'), 28.5);
      expect(parseRolandWardMinimumValue('16 1/2 inches'), 16.5);
      expect(parseRolandWardMinimumValue('22 7/8 inches'), 22.875);
    });

    test('respects fraction precedence over substrings', () {
      // Legacy behavior would drop non-numeric chars; ensure the modern
      // parser never returns a wildly inflated value.
      final value = parseRolandWardMinimumValue('22 7/8 inches');
      expect(value, isNot(2278));
      expect(value! < 23, isTrue);
    });

    test('returns null for empty / malformed input', () {
      expect(parseRolandWardMinimumValue(null), isNull);
      expect(parseRolandWardMinimumValue(''), isNull);
      expect(parseRolandWardMinimumValue('   '), isNull);
      expect(parseRolandWardMinimumValue('none'), isNull);
    });
  });

  group('Field Estimate qualification comparison', () {
    bool qualifies(double estimate, double minimum) => estimate >= minimum;

    test('an estimate exceeding the minimum qualifies', () {
      // Screenshot 3 regression: 30.00 vs the 22 7/8 minimum — must qualify.
      final minimum = parseRolandWardMinimumValue('22 7/8 inches')!;
      expect(qualifies(30.00, minimum), isTrue);
    });

    test('an estimate equal to the minimum qualifies', () {
      final minimum = parseRolandWardMinimumValue('22 7/8 inches')!;
      expect(qualifies(minimum, minimum), isTrue);
    });

    test('an estimate below the minimum does not qualify', () {
      final minimum = parseRolandWardMinimumValue('22 7/8 inches')!;
      expect(qualifies(22.0, minimum), isFalse);
    });

    test('the screen uses the shared parser', () {
      final src =
          File('lib/features/game_guide/presentation/field_estimate_screen.dart')
              .readAsStringSync();
      expect(src.contains('parseRolandWardMinimumValue'), isTrue);
      // The comparison operator reports qualification when estimate >= min.
      expect(
        src.contains(
          'meetsMinimum = comparableHornLength >= comparableMinimumValue;',
        ),
        isTrue,
      );
    });

    test('the seeder table minimums parse to plausible benchmark values', () {
      // Every listed species' minimum must resolve to a single-digit or
      // two-digit-inch value — the legacy 2278-style inflation must never
      // reappear across any species record.
      for (final species in getRolandWardSpeciesNames()) {
        final metrics = getRolandWardMetricsForSpecies(species);
        final minimum = parseRolandWardMinimumValue(metrics!.rwMinimum);
        expect(minimum, isNotNull, reason: species);
        expect(minimum!, greaterThan(0), reason: species);
        expect(minimum, lessThan(100), reason: species);
      }
    });
  });
}
