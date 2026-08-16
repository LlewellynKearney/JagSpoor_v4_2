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
        gender: 'Male',
        hornTuskLength: '28"+',
        hornTuskUnit: HornTuskUnit.cm,
        createdAt: created,
        updatedAt: created,
      );
      final map = entry.toMap();
      expect(map['farmId'], 'farm-1');
      expect(map['outfitterId'], 'outfitter-uid');
      expect(map['speciesName'], 'Impala');
      expect(map['qty'], 5);
      expect(map['price'], 2500.0);
      expect(map['gender'], 'Male');
      expect(map['hornTuskLength'], '28"+');
      expect(map['hornTuskUnit'], HornTuskUnit.cm);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());

      final restored = FarmGamePriceEntry.fromMap(map, id: 'entry-1');
      expect(restored.id, 'entry-1');
      expect(restored.farmId, 'farm-1');
      expect(restored.outfitterId, 'outfitter-uid');
      expect(restored.speciesName, 'Impala');
      expect(restored.qty, 5);
      expect(restored.priceZAR, 2500.0);
      expect(restored.gender, 'Male');
      expect(restored.hornTuskLength, '28"+');
      expect(restored.hornTuskUnit, HornTuskUnit.cm);
      // Firestore Timestamp.toDate() returns a local DateTime, so compare via
      // millisecondsSinceEpoch (timezone-independent).
      expect(restored.createdAt?.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
      expect(restored.updatedAt?.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
    });

    test('omits hornTuskLength from toMap when empty', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Impala',
        qty: 1,
        priceZAR: 100,
      );
      final map = entry.toMap();
      expect(map.containsKey('hornTuskLength'), isFalse);
      expect(map['gender'], 'Any');
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

    test('defaults gender to Any + hornTuskLength to empty when missing', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Impala', 'qty': 1, 'price': 100},
        id: 'x',
      );
      expect(entry.gender, 'Any');
      expect(entry.hornTuskLength, '');
    });

    test('normalizes gender aliases (sex, M/F, bull/cow, both)', () {
      expect(
        FarmGamePriceEntry.fromMap({'gender': 'male'}, id: 'x').gender,
        'Male',
      );
      expect(
        FarmGamePriceEntry.fromMap({'sex': 'F'}, id: 'x').gender,
        'Female',
      );
      expect(
        FarmGamePriceEntry.fromMap({'gender': 'Bull'}, id: 'x').gender,
        'Male',
      );
      expect(
        FarmGamePriceEntry.fromMap({'gender': 'cow'}, id: 'x').gender,
        'Female',
      );
      expect(
        FarmGamePriceEntry.fromMap({'gender': 'Both'}, id: 'x').gender,
        'Any',
      );
    });

    test('tolerates hornTuskLength aliases "horn" / "tusk"', () {
      expect(
        FarmGamePriceEntry.fromMap({'horn': 'Trophy'}, id: 'x').hornTuskLength,
        'Trophy',
      );
      expect(
        FarmGamePriceEntry.fromMap({'tusk': '30" +'}, id: 'x').hornTuskLength,
        '30" +',
      );
    });

    test('trims the species name + horn/tusk length on read', () {
      final entry = FarmGamePriceEntry.fromMap(
        {'speciesName': '  Impala  ', 'qty': 1, 'price': 100, 'hornTuskLength': '  28"  '},
        id: 'x',
      );
      expect(entry.speciesName, 'Impala');
      expect(entry.hornTuskLength, '28"');
    });

    test('copyWith updates only the supplied fields + preserves the rest', () {
      final entry = FarmGamePriceEntry(
        id: 'e1',
        farmId: 'f1',
        outfitterId: 'o1',
        speciesName: 'Impala',
        qty: 2,
        priceZAR: 1000,
        gender: 'Male',
        hornTuskLength: '28"',
      );
      final updated = entry.copyWith(qty: 8, priceZAR: 1750);
      expect(updated.id, 'e1');
      expect(updated.farmId, 'f1');
      expect(updated.speciesName, 'Impala'); // preserved
      expect(updated.qty, 8);
      expect(updated.priceZAR, 1750);
      expect(updated.gender, 'Male'); // preserved
      expect(updated.hornTuskLength, '28"'); // preserved
    });

    test('copyWith can update gender + hornTuskLength', () {
      final entry = FarmGamePriceEntry(
        id: 'e1',
        farmId: 'f1',
        outfitterId: 'o1',
        speciesName: 'Impala',
        qty: 2,
        priceZAR: 1000,
      );
      final updated = entry.copyWith(gender: 'Female', hornTuskLength: 'Cull');
      expect(updated.gender, 'Female');
      expect(updated.hornTuskLength, 'Cull');
      expect(updated.speciesName, 'Impala'); // preserved
    });
  });

  group('FarmGamePriceValidator.genderOptions', () {
    test('contains Male, Female, Any', () {
      expect(FarmGamePriceValidator.genderOptions, ['Male', 'Female', 'Any']);
    });
    test('default gender is Any', () {
      expect(FarmGamePriceValidator.defaultGender, 'Any');
    });
  });

  group('FarmGamePriceValidator.validateHornTuskLength', () {
    test('accepts null + empty (optional field)', () {
      expect(FarmGamePriceValidator.validateHornTuskLength(null), isNull);
      expect(FarmGamePriceValidator.validateHornTuskLength(''), isNull);
      expect(FarmGamePriceValidator.validateHornTuskLength('   '), isNull);
    });
    test('accepts a valid descriptor', () {
      expect(FarmGamePriceValidator.validateHornTuskLength('28"+'), isNull);
      expect(FarmGamePriceValidator.validateHornTuskLength('Trophy'), isNull);
      expect(FarmGamePriceValidator.validateHornTuskLength('Cull'), isNull);
    });
    test('rejects values longer than 40 chars', () {
      expect(FarmGamePriceValidator.validateHornTuskLength('x' * 41), isNotNull);
      expect(FarmGamePriceValidator.validateHornTuskLength('x' * 40), isNull);
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

  group('HornTuskUnit', () {
    test('normalize accepts canonical values', () {
      expect(HornTuskUnit.normalize('inches'), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('cm'), HornTuskUnit.cm);
    });
    test('normalize accepts common aliases case-insensitively', () {
      expect(HornTuskUnit.normalize('IN'), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('in.'), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('inch'), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('"'), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('Centimeters'), HornTuskUnit.cm);
      expect(HornTuskUnit.normalize('centimetre'), HornTuskUnit.cm);
    });
    test('normalize defaults to inches for null/unknown/legacy', () {
      expect(HornTuskUnit.normalize(null), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize(''), HornTuskUnit.inches);
      expect(HornTuskUnit.normalize('parsecs'), HornTuskUnit.inches);
    });
    test('label returns short selector text', () {
      expect(HornTuskUnit.label(HornTuskUnit.inches), 'in');
      expect(HornTuskUnit.label(HornTuskUnit.cm), 'cm');
    });
    test('suffix returns display suffix with leading space', () {
      expect(HornTuskUnit.suffix(HornTuskUnit.inches), ' (in)');
      expect(HornTuskUnit.suffix(HornTuskUnit.cm), ' cm');
    });
    test('options lists inches then cm', () {
      expect(HornTuskUnit.options, [HornTuskUnit.inches, HornTuskUnit.cm]);
    });
  });

  group('FarmGamePriceEntry.hornTuskDisplayLabel', () {
    test('appends the unit suffix to the length value', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
        hornTuskLength: '28"+',
        hornTuskUnit: HornTuskUnit.inches,
      );
      expect(entry.hornTuskDisplayLabel, '28"+ (in)');
    });
    test('appends cm suffix when unit is cm', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
        hornTuskLength: '70',
        hornTuskUnit: HornTuskUnit.cm,
      );
      expect(entry.hornTuskDisplayLabel, '70 cm');
    });
    test('returns empty string when no length is set', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
      );
      expect(entry.hornTuskDisplayLabel, '');
    });
    test('defaults to inches when unit is unset', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
        hornTuskLength: '40',
      );
      expect(entry.hornTuskUnit, HornTuskUnit.inches);
      expect(entry.hornTuskDisplayLabel, '40 (in)');
    });
  });

  group('FarmGamePriceEntry.hornTuskUnit persistence', () {
    test('fromMap reads hornTuskUnit + defaults to inches when absent', () {
      final restored = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Impala', 'qty': 2, 'price': 500, 'hornTuskLength': '30"'},
        id: 'e',
      );
      expect(restored.hornTuskUnit, HornTuskUnit.inches);
    });
    test('fromMap normalizes a stored cm value', () {
      final restored = FarmGamePriceEntry.fromMap(
        {'speciesName': 'Impala', 'qty': 2, 'price': 500, 'hornTuskUnit': 'centimeters'},
        id: 'e',
      );
      expect(restored.hornTuskUnit, HornTuskUnit.cm);
    });
    test('copyWith updates hornTuskUnit only', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
        hornTuskLength: '40',
      );
      final updated = entry.copyWith(hornTuskUnit: HornTuskUnit.cm);
      expect(updated.hornTuskUnit, HornTuskUnit.cm);
      expect(updated.speciesName, 'Kudu');
      expect(updated.hornTuskLength, '40');
    });
    test('toMap always writes hornTuskUnit even when length is empty', () {
      final entry = FarmGamePriceEntry(
        id: 'e',
        farmId: 'f',
        outfitterId: 'o',
        speciesName: 'Kudu',
        qty: 1,
        priceZAR: 1000,
        hornTuskUnit: HornTuskUnit.cm,
      );
      final map = entry.toMap();
      expect(map['hornTuskUnit'], HornTuskUnit.cm);
      expect(map.containsKey('hornTuskLength'), isFalse);
    });
  });
}
