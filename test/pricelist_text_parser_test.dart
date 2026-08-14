import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/pricelist_text_parser.dart';

void main() {
  group('parsePrice', () {
    test('parses SA space-thousand separator', () {
      expect(parsePrice('12 500'), 12500);
    });

    test('parses R-prefixed space thousands', () {
      expect(parsePrice('R 12 500'), 12500);
    });

    test('parses comma thousands (US/legacy)', () {
      expect(parsePrice('12,500'), 12500);
    });

    test('parses comma decimal with two trailing digits', () {
      expect(parsePrice('12500,00'), 12500);
    });

    test('parses dot-thousands + comma-decimal (European)', () {
      expect(parsePrice('1.234,56'), 1234.56);
    });

    test('parses comma-thousands + dot-decimal (US)', () {
      expect(parsePrice('1,234.56'), 1234.56);
    });

    test('parses plain integer', () {
      expect(parsePrice('8500'), 8500);
    });

    test('returns null on garbage', () {
      expect(parsePrice('abc'), isNull);
    });
  });

  group('PricelistTextParser dynamic extraction', () {
    final parser = PricelistTextParser();

    test('parses an English price list into structured items', () {
      final raw = '''
Kudu Bull >50"           R 18 500
Impala Ram               R 3 500
Warthog                  R 2 500
Springbok                R 2 800
Blue Wildebeest          R 5 500
Daily Rate (PH Included) R 2 000
Slaughter Fee            R 450
Accommodation per night  R 1 500
''';
      final items = parser.parse(raw);

      expect(items.length, 8);

      final kudu = items.firstWhere((i) => i.speciesId == 'Greater Kudu');
      expect(kudu.sex, 'Male');
      expect(kudu.sexLabel, 'bull');
      expect(kudu.trophySizeRange, '>50"');
      expect(kudu.priceZAR, 18500);
      expect(kudu.itemType, 'species');

      final impala = items.firstWhere((i) => i.speciesId == 'Impala');
      expect(impala.sex, 'Male');
      expect(impala.sexLabel, 'ram');
      expect(impala.priceZAR, 3500);

      expect(items.any((i) => i.speciesId == 'Common Warthog'), isTrue);
      expect(items.any((i) => i.speciesId == 'Springbok'), isTrue);
      expect(items.any((i) => i.speciesId == 'Blue Wildebeest'), isTrue);

      final daily = items.firstWhere((i) => i.itemType == 'fee');
      expect(daily.feeType, 'daily');
      expect(daily.priceZAR, 2000);

      final slaughter = items.firstWhere((i) => i.feeType == 'slaughter');
      expect(slaughter.priceZAR, 450);

      final accom = items.firstWhere((i) => i.feeType == 'accommodation');
      expect(accom.priceZAR, 1500);
    });

    test('different inputs produce different outputs (no hardcoded mock)', () {
      final a = parser.parse('Kudu R 12 000\nImpala R 3 000');
      final b = parser.parse('Eland R 9 500\nGemsbok R 8 000\nNyala R 11 000');
      expect(a.length, 2);
      expect(b.length, 3);
      expect(a.first.speciesId, 'Greater Kudu');
      expect(b.first.speciesId, 'Eland');
      expect(a.any((i) => i.speciesId == 'Eland'), isFalse);
      expect(b.any((i) => i.speciesId == 'Greater Kudu'), isFalse);
    });

    test('skips lines with no parseable price', () {
      final items = parser.parse('Kudu >50"\nImpala R 3 000\nheader line');
      expect(items.length, 1);
      expect(items.first.speciesId, 'Impala');
    });

    test('de-duplicates identical species/sex/size rows', () {
      final items = parser.parse(
        'Kudu Bull >50" R 18 500\nKudu Bull >50" R 18 500',
      );
      expect(items.length, 1);
    });
  });

  group('Afrikaans species + terminology recognition', () {
    final parser = PricelistTextParser();

    test('maps every required Afrikaans species to a system species id', () {
      final cases = <String, String>{
        'Vlakvark R 2 500': 'Common Warthog',
        'Blesbok R 4 200': 'Blesbok',
        'Springbok R 2 800': 'Springbok',
        'Rooibok R 3 500': 'Impala',
        'Koedoe R 15 000': 'Greater Kudu',
        'Blouwildebees R 5 500': 'Blue Wildebeest',
        'Gemsbok R 8 500': 'Gemsbok (Oryx)',
        'Eland R 12 000': 'Eland',
        'Bosbok R 6 000': 'Southern Bushbuck',
        'Waterbok R 7 500': 'Common Waterbuck',
        'Rooihartbees R 6 500': 'Red Hartebeest',
        'Nyala R 9 500': 'Nyala',
        'Sebra R 4 500': 'Plains Zebra',
        'Duiker R 3 000': 'Common Duiker',
        'Steenbok R 2 000': 'Steenbok',
        'Takbok R 5 000': 'Fallow Deer',
      };
      for (final entry in cases.entries) {
        final items = parser.parse(entry.key);
        expect(items.length, 1, reason: '${entry.key} produced no item');
        expect(items.first.speciesId, entry.value,
            reason: '${entry.key} mapped wrong');
        expect(items.first.itemType, 'species');
      }
    });

    test('preserves original Afrikaans display label', () {
      final items = parser.parse('Koedoe Bul >50" R 18 500');
      expect(items.length, 1);
      expect(items.first.displayLabel, 'Koedoe Bul >50" R 18 500');
      expect(items.first.speciesId, 'Greater Kudu');
      expect(items.first.speciesName, 'Greater Kudu');
    });

    test('recognises Afrikaans sex/class tokens', () {
      expect(parser.parse('Koedoe Bul R 15 000').first.sex, 'Male');
      expect(parser.parse('Koedoe Ram R 15 000').first.sex, 'Male');
      expect(parser.parse('Blesbok Koei R 4 000').first.sex, 'Female');
      expect(parser.parse('Blesbok Ooi R 4 000').first.sex, 'Female');
      expect(parser.parse('Koedoe Jongbul R 9 000').first.sex, 'Young Male');
      expect(parser.parse('Blesbok Penkop R 3 500').first.sex, 'Young Male');
      expect(parser.parse('Blesbok Knypkop R 3 000').first.sex, 'Young Male');
    });

    test('recognises Afrikaans fee terms', () {
      expect(parser.parse('Dagfooi R 2 000').first.feeType, 'daily');
      expect(parser.parse('Slagfooi R 450').first.feeType, 'slaughter');
      expect(parser.parse('Gidskoste R 1 200').first.feeType, 'guide');
      expect(parser.parse('Wildrit R 800').first.feeType, 'gamedrive');
      expect(parser.parse('Bakkiefooi R 1 500').first.feeType, 'vehicle');
    });

    test('recognises trophy size ranges including brackets', () {
      expect(parser.parse('Koedoe >50" R 20 000').first.trophySizeRange, '>50"');
      expect(parser.parse('Springbok <20" R 2 000').first.trophySizeRange, '<20"');
      expect(parser.parse('Blesbok 40"-50" R 6 000').first.trophySizeRange,
          '40"-50"');
      expect(parser.parse('Kudu 50"+ R 25 000').first.trophySizeRange, '50"+');
    });

    test('word-boundary: "ram" does not match inside "framing"', () {
      final items = parser.parse('Framing service R 500');
      expect(items, isEmpty);
    });
  });

  group('GeminiResultNormalizer', () {
    test('normalises Gemini JSON with Afrikaans labels to system ids', () {
      final json = jsonEncode([
        {
          'type': 'species',
          'species': 'Koedoe',
          'sex': 'Bul',
          'sizeRange': '>50"',
          'priceZAR': 18500,
          'displayLabel': 'Koedoe Bul >50"',
        },
        {
          'type': 'species',
          'species': 'Rooibok',
          'sex': 'Koei',
          'sizeRange': '',
          'priceZAR': 3000,
          'displayLabel': 'Rooibok Koei',
        },
        {
          'type': 'fee',
          'species': '',
          'feeType': 'daily',
          'priceZAR': 2000,
          'displayLabel': 'Dagfooi',
        },
      ]);
      final items = parseGeminiTextResponse(json);
      expect(items.length, 3);
      expect(items[0].speciesId, 'Greater Kudu');
      expect(items[0].sex, 'Male');
      expect(items[0].trophySizeRange, '>50"');
      expect(items[1].speciesId, 'Impala');
      expect(items[1].sex, 'Female');
      expect(items[2].itemType, 'fee');
      expect(items[2].feeType, 'daily');
    });

    test('string price is parsed through SA separator logic', () {
      final items = GeminiResultNormalizer.normalize([
        {
          'type': 'species',
          'species': 'Kudu',
          'priceZAR': 'R 18 500',
        },
      ]);
      expect(items.single.priceZAR, 18500);
    });

    test('falls back to text parsing when response is not JSON', () {
      final items = parseGeminiTextResponse('Impala R 3 500\nKudu R 12 000');
      expect(items.length, 2);
      expect(items.first.speciesId, 'Impala');
    });
  });

  group('PricelistItem.toMap', () {
    test('round-trips all fields', () {
      final item = PricelistItem(
        displayLabel: 'Koedoe Bul >50"',
        speciesName: 'Greater Kudu',
        speciesId: 'Greater Kudu',
        sex: 'Male',
        sexLabel: 'bul',
        trophySizeRange: '>50"',
        priceZAR: 18500,
        itemType: 'species',
        feeType: '',
      );
      final m = item.toMap();
      expect(m['displayLabel'], 'Koedoe Bul >50"');
      expect(m['name'], 'Koedoe Bul >50"');
      expect(m['speciesId'], 'Greater Kudu');
      expect(m['outfitterBasePrice'], 18500);
      expect(m['trophySizeRange'], '>50"');
    });
  });
}
