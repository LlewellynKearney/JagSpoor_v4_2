import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/trophy_share_composer.dart';

void main() {
  group('TrophyShareComposer.buildTrophyShareMessage', () {
    test('full trophy renders all four lines with measurements', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Greater Kudu',
        'harvestDate': '2026-08-12',
        'antlerSpread': 53.875,
        'antlerLength': 48.0,
        'antlerCircumference': 10.5,
        'weight': 240,
        'location': 'Eastern Cape',
        'firearmUsed': 'Tikka T3x (.308 Win)',
      });

      expect(message, startsWith('🦌 Check out my latest harvest on JagSpoor!'));
      expect(message, contains('Species: Greater Kudu'));
      expect(message, contains('Spread 53.9 cm'));
      expect(message, contains('Length 48 cm'));
      expect(message, contains('Circumference 10.5 cm'));
      expect(message, contains('Weight 240 kg'));
      expect(message, contains('Date: 2026-08-12'));
      expect(message, endsWith('Shared via JagSpoor App'));
      // Score line is the second line after the header.
      final scoreLine = message.split('\n').firstWhere(
        (l) => l.startsWith('Score / Details:'),
      );
      expect(
        scoreLine,
        'Score / Details: Spread 53.9 cm • Length 48 cm • '
        'Circumference 10.5 cm • Weight 240 kg',
      );
    });

    test('missing species falls back to Unknown Trophy', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'harvestDate': '2026-01-01',
        'weight': 120,
      });
      expect(message, contains('Species: Unknown Trophy'));
    });

    test('no measurements renders N/A for Score / Details', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Springbok',
        'harvestDate': '2026-03-15',
      });
      expect(message, contains('Score / Details: N/A'));
    });

    test('partial measurements only include present fields', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Impala',
        'harvestDate': '2026-04-20',
        'antlerSpread': 23.0,
        'weight': 55.5,
      });
      final scoreLine = message.split('\n').firstWhere(
        (l) => l.startsWith('Score / Details:'),
      );
      expect(scoreLine, 'Score / Details: Spread 23 cm • Weight 55.5 kg');
      expect(scoreLine, isNot(contains('Length')));
      expect(scoreLine, isNot(contains('Circumference')));
    });

    test('missing or blank harvest date falls back to N/A', () {
      final noDate = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Warthog',
      });
      expect(noDate, contains('Date: N/A'));

      final blankDate = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Warthog',
        'harvestDate': '',
      });
      expect(blankDate, contains('Date: N/A'));
    });

    test('malformed date is shown verbatim (best-effort)', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Eland',
        'harvestDate': 'not-a-date',
      });
      expect(message, contains('Date: not-a-date'));
    });

    test('numeric measurement stored as string is parsed', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Nyala',
        'harvestDate': '2026-05-01',
        'antlerSpread': '27.5',
        'weight': '92',
      });
      expect(message, contains('Spread 27.5 cm'));
      expect(message, contains('Weight 92 kg'));
    });

    test('null measurement values are skipped, not rendered as 0', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Blesbok',
        'harvestDate': '2026-06-10',
        'antlerSpread': null,
        'antlerLength': null,
        'antlerCircumference': null,
        'weight': null,
      });
      expect(message, contains('Score / Details: N/A'));
    });

    test('whole-number measurements render without trailing .0', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Blue Wildebeest',
        'harvestDate': '2026-07-04',
        'antlerSpread': 28.0,
        'weight': 160.0,
      });
      expect(message, contains('Spread 28 cm'));
      expect(message, contains('Weight 160 kg'));
    });

    test('message structure is exactly four content lines + header', () {
      final message = TrophyShareComposer.buildTrophyShareMessage({
        'species': 'Gemsbok',
        'harvestDate': '2026-02-18',
        'antlerLength': 40.0,
      });
      final lines = message.split('\n');
      expect(lines.length, 5);
      expect(lines[0], '🦌 Check out my latest harvest on JagSpoor!');
      expect(lines[1], 'Species: Gemsbok');
      expect(lines[2], 'Score / Details: Length 40 cm');
      expect(lines[3], 'Date: 2026-02-18');
      expect(lines[4], 'Shared via JagSpoor App');
    });
  });

  group('TrophyShareComposer default subject', () {
    test('default subject is the expected marketing string', () {
      expect(TrophyShareComposer.defaultSubject, 'My JagSpoor Trophy!');
    });
  });
}
