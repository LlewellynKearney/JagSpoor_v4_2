import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_game_price_entry.dart';

/// Unit tests for the farm game price-list model + form validators.
///
/// The Firestore-backed stream cannot run in this sandbox (no emulator), so
/// these tests lock in the pure model parsing (`fromMap` / `toMap`
/// round-trips + field-alias tolerance) and the form-validation contract
/// (species / qty / price rules) that the add/edit sheet enforces before
/// calling the manager.
void main() {
  group('FarmGamePriceEntry.fromMap', () {
    test('round-trips every field through toMap', () {
      final created = DateTime.utc(2026, 8, 16, 10, 0);
      final entry = FarmGamePriceEntry(
        id: 'entry-1',
        farmId: 'farm-1',
        outfitterId: 'outfitter-uid',
        speciesName: 'Impala',
        qty: 5,
        priceZAR: 2500.0,
        createdAt: created,
        updatedAt: created,
      );
      final map = entry.toMap();
      expect(map['farmId'], 'farm-1');
      expect(map['outfitterId'], 'outfitter-uid');
      expect(map['speciesName'], 'Impala');
      expect(map['qty'], 5);
      expect(map['price'], 2500.0);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());

      final restored = FarmGamePriceEntry.fromMap(map, id: 'entry-1');
      expect(restored.id, 'entry-1');
      expect(restored.farmId, 'farm-1');
      expect(restored.outfitterId, 'outfitter-uid');
      expect(restored.speciesName, 'Impala');
      expect(restored.qty, 5);
      expect(restored.priceZAR, 2500.0);
      // Firestore Timestamp.toDate() returns a local DateTime, so compare via
      // millisecondsSinceEpoch (timezone-independent).
      expect(restored.createdAt?.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
      expect(restored.updatedAt?.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
    });

    test('tolerates speciesName alias "name"', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'farmId': 'f', 'outfitterId': 'o', 'name': 'Kudu', 'qty': 2, 'price': 3500},
        id: 'x',
      );
      expect(entry.speciesName, 'Kudu');
    });

    test('tolerates qty alias "quantity"', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Springbok', 'quantity': 10, 'price': 1200},
        id: 'x',
      );
      expect(entry.qty, 10);
    });

    test('tolerates price aliases "priceZAR" / "priceRands"', () {
      final a = FarmGamePriceEntry.fromMap(
        {'speciesName': 'S', 'qty': 1, 'priceZAR': 900},
        id: 'x',
      );
      expect(a.priceZAR, 900.0);
      final b = FarmGamePriceEntry.fromMap(
        {'speciesName': 'S', 'qty': 1, 'priceRands': 750.5},
        id: 'x',
      );
      expect(b.priceZAR, 750.5);
    });

    test('parses numeric strings (qty + price)', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Warthog', 'qty': '3', 'price': 'R 1 500'},
        id: 'x',
      );
      expect(entry.qty, 3);
      expect(entry.priceZAR, 1500.0);
    });

    test('defaults to 0 for missing / invalid numerics', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Eland', 'qty': 'abc', 'price': null},
        id: 'x',
      );
      expect(entry.qty, 0);
      expect(entry.priceZAR, 0.0);
    });

    test('defaults to empty strings for missing farm/outfitter/species', () {
      final entry = FarmGamePriceEntry.fromMap(
        const <String, dynamic>{},
        id: 'x',
      );
      expect(entry.farmId, '');
      expect(entry.outfitterId, '');
      expect(entry.speciesName, '');
    });

    test('trims the species name on read', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': '  Impala  ', 'qty': 1, 'price': 100},
        id: 'x',
      );
      expect(entry.speciesName, 'Impala');
    });

    test('copyWith updates only the supplied fields + preserves the rest', () {
      final entry = FarmGamePriceEntry(
        id: 'e1',
        farmId: 'f1',
        outfitterId: 'o1',
        speciesName: 'Impala',
        qty: 2,
        priceZAR: 1000,
      );
      final updated = entry.copyWith(qty: 8, priceZAR: 1750);
      expect(updated.id, 'e1');
      expect(updated.farmId, 'f1');
      expect(updated.speciesName, 'Impala'); // preserved
      expect(updated.qty, 8);
      expect(updated.priceZAR, 1750);
    });
  });

  group('FarmGamePriceValidator.validateSpecies', () {
    test('rejects empty / whitespace', () {
      expect(FarmGamePriceValidator.validateSpecies(''), isNotNull);
      expect(FarmGamePriceValidator.validateSpecies('   '), isNotNull);
      expect(FarmGamePriceValidator.validateSpecies(null), isNotNull);
    });
    test('accepts a valid species name', () {
      expect(FarmGamePriceValidator.validateSpecies('Impala'), isNull);
      expect(FarmGamePriceValidator.validateSpecies(' Greater Kudu '), isNull);
    });
    test('rejects names longer than 80 chars', () {
      expect(FarmGamePriceValidator.validateSpecies('x' * 81), isNotNull);
      expect(FarmGamePriceValidator.validateSpecies('x' * 80), isNull);
    });
  });

  group('FarmGamePriceValidator.validateQty', () {
    test('rejects empty', () {
      expect(FarmGamePriceValidator.validateQty(''), isNotNull);
      expect(FarmGamePriceValidator.validateQty(null), isNotNull);
    });
    test('rejects non-numeric', () {
      expect(FarmGamePriceValidator.validateQty('abc'), isNotNull);
      expect(FarmGamePriceValidator.validateQty('1.5'), isNotNull,
          reason: 'qty must be a whole number');
    });
    test('rejects negative', () {
      expect(FarmGamePriceValidator.validateQty('-1'), isNotNull);
    });
    test('accepts valid whole numbers incl. zero', () {
      expect(FarmGamePriceValidator.validateQty('0'), isNull);
      expect(FarmGamePriceValidator.validateQty('5'), isNull);
      expect(FarmGamePriceValidator.validateQty(' 12 '), isNull);
    });
  });

  group('FarmGamePriceValidator.validatePrice', () {
    test('rejects empty', () {
      expect(FarmGamePriceValidator.validatePrice(''), isNotNull);
      expect(FarmGamePriceValidator.validatePrice(null), isNotNull);
    });
    test('rejects non-numeric', () {
      expect(FarmGamePriceValidator.validatePrice('abc'), isNotNull);
    });
    test('rejects negative', () {
      expect(FarmGamePriceValidator.validatePrice('-50'), isNotNull);
    });
    test('accepts valid numbers incl. decimals + strips R prefix', () {
      expect(FarmGamePriceValidator.validatePrice('2500'), isNull);
      expect(FarmGamePriceValidator.validatePrice('2500.50'), isNull);
      expect(FarmGamePriceValidator.validatePrice('R 2500'), isNull);
      expect(FarmGamePriceValidator.validatePrice('r 99.9'), isNull);
    });
    test('accepts zero', () {
      expect(FarmGamePriceValidator.validatePrice('0'), isNull);
    });
  });
}
