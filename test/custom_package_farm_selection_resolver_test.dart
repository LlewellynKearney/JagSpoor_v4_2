import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/screens/custom_package_farm_selection_screen.dart';

/// Unit tests for `resolveOutfittersByFarm` -- the `farmId -> outfitterId`
/// resolution the Custom Package Builder farm-selection screen applies to the
/// raw `farm_pricelists` documents.
///
/// Regression guard for the orphaned-booking bug: the previous `putIfAbsent`
/// implementation kept the FIRST entry's `outfitterId` even when it was
/// empty, so a farm whose earliest-written price-list entry had a blank
/// `outfitterId` resolved to `''` and the builder wrote a booking the
/// outfitter never saw (their dashboard queries `outfitterId == uid`). The
/// fix keeps the first entry that carries a NON-EMPTY `outfitterId`.
void main() {
  group('resolveOutfittersByFarm', () {
    test('maps each farm to its outfitter id', () {
      final result = resolveOutfittersByFarm([
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-1'},
        {'farmId': 'farm-2', 'outfitterId': 'outfitter-2'},
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-1'},
      ]);

      expect(result, {
        'farm-1': 'outfitter-1',
        'farm-2': 'outfitter-2',
      });
    });

    test('a later entry with a non-empty outfitterId backfills an empty one',
        () {
      // The first entry for the farm has a blank outfitterId (stale /
      // hand-written doc); a later entry carries the real one. The non-empty
      // value must win (this is the bug fix).
      final result = resolveOutfittersByFarm([
        {'farmId': 'farm-1', 'outfitterId': ''},
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-1'},
      ]);

      expect(result['farm-1'], 'outfitter-1');
    });

    test('a later entry with a non-empty outfitterId backfills a MISSING one',
        () {
      final result = resolveOutfittersByFarm([
        {'farmId': 'farm-1'}, // no outfitterId key at all
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-1'},
      ]);

      expect(result['farm-1'], 'outfitter-1');
    });

    test('a known non-empty outfitterId is never overwritten by a later '
        'blank or different value', () {
      final result = resolveOutfittersByFarm([
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-1'},
        {'farmId': 'farm-1', 'outfitterId': ''},
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-OTHER'},
      ]);

      // First non-empty wins; subsequent entries (blank or otherwise) do not
      // replace it -- the farm's price list belongs to exactly one outfitter.
      expect(result['farm-1'], 'outfitter-1');
    });

    test('skips entries with a missing or blank farmId', () {
      final result = resolveOutfittersByFarm([
        {'outfitterId': 'outfitter-1'}, // no farmId
        {'farmId': '', 'outfitterId': 'outfitter-2'},
        {'farmId': 'farm-1', 'outfitterId': 'outfitter-3'},
      ]);

      expect(result, hasLength(1));
      expect(result['farm-1'], 'outfitter-3');
      expect(result.containsKey(''), isFalse);
    });

    test('returns an empty map for an empty collection', () {
      expect(resolveOutfittersByFarm(const []), isEmpty);
    });

    test('a farm whose every entry lacks an outfitterId resolves to empty '
        '(the builder guard surfaces a clear error instead of an orphaned '
        'booking)', () {
      final result = resolveOutfittersByFarm([
        {'farmId': 'farm-1', 'outfitterId': ''},
        {'farmId': 'farm-1'},
      ]);

      expect(result['farm-1'], '');
    });
  });
}
