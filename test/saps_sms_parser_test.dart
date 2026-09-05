import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_sms_parser.dart';

void main() {
  group('SapsSmsParser.parse — reference extraction', () {
    test('extracts the reference from the canonical SAPS message', () {
      final result = SapsSmsParser.parse(
        'SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(result.referenceNumber, '10470664');
      expect(result.calibre, '6MM MUSGRAVE');
      expect(result.serialNumber, 'OB14468');
    });

    test('extracts the reference from "Reference 10470664"', () {
      final result = SapsSmsParser.parse(
        'SAPS: Reference 10470664 Calibre 6MM MUSGRAVE Serial OB14468',
      );
      expect(result.referenceNumber, '10470664');
      expect(result.calibre, '6MM MUSGRAVE');
      expect(result.serialNumber, 'OB14468');
    });

    test('extracts the reference from "Ref 10470664"', () {
      final result = SapsSmsParser.parse(
        'Your application Ref 10470664 has been received',
      );
      expect(result.referenceNumber, '10470664');
    });

    test('extracts the reference from "Ref No 10470664"', () {
      final result = SapsSmsParser.parse('Ref No 10470664 status update');
      expect(result.referenceNumber, '10470664');
    });

    test('extracts the reference from "Application Reference 10470664"', () {
      final result = SapsSmsParser.parse(
        'Application Reference 10470664 is now at CFR',
      );
      expect(result.referenceNumber, '10470664');
    });

    test('extracts the reference from a URL query param', () {
      final result = SapsSmsParser.parse(
        'https://www.saps.org.za/status-check?reference=10470664',
      );
      expect(result.referenceNumber, '10470664');
    });

    test('returns empty reference for a message without one', () {
      final result = SapsSmsParser.parse(
        'Your licence has been approved. Please collect at your DFO.',
      );
      expect(result.referenceNumber, '');
    });

    test('returns empty result for null / empty input', () {
      expect(SapsSmsParser.parse(null).isEmpty, isTrue);
      expect(SapsSmsParser.parse('').isEmpty, isTrue);
      expect(SapsSmsParser.parse('   ').isEmpty, isTrue);
    });
  });

  group('SapsSmsParser.parse — calibre extraction', () {
    test('extracts a calibre with a model name', () {
      final result = SapsSmsParser.parse(
        'Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(result.calibre, '6MM MUSGRAVE');
    });

    test('extracts a numeric calibre with unit', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 calibre 308 WIN serial ABC123',
      );
      expect(result.calibre, '308 WIN');
    });

    test('extracts a 9mm calibre', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 calibre 9MM PARABELLUM serial ABC123',
      );
      expect(result.calibre, '9MM PARABELLUM');
    });

    test('extracts a decimal calibre', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 calibre 6.5 CREEDMOOR serial ABC123',
      );
      expect(result.calibre, '6.5 CREEDMOOR');
    });

    test('extracts a bare numeric calibre', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 calibre 6MM serial ABC123',
      );
      expect(result.calibre, '6MM');
    });

    test('returns empty calibre when none present', () {
      final result = SapsSmsParser.parse(
        'Application Ref. 10470664 has been approved',
      );
      expect(result.calibre, '');
    });
  });

  group('SapsSmsParser.parse — serial number extraction', () {
    test('extracts s/n serial', () {
      final result = SapsSmsParser.parse(
        'SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(result.serialNumber, 'OB14468');
    });

    test('extracts "serial" serial', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 calibre 308 WIN serial ABC123',
      );
      expect(result.serialNumber, 'ABC123');
    });

    test('extracts "serial number" serial', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 serial number X9-42K serial',
      );
      expect(result.serialNumber, 'X9-42K');
    });

    test('extracts a serial with embedded hyphen', () {
      final result = SapsSmsParser.parse(
        'Ref 12345 s/n AB-1234-CD',
      );
      expect(result.serialNumber, 'AB-1234-CD');
    });

    test('returns empty serial when none present', () {
      final result = SapsSmsParser.parse(
        'Application Ref. 10470664 has been approved',
      );
      expect(result.serialNumber, '');
    });
  });

  group('SapsSmsParser.parse — status extraction', () {
    test('detects a collection notice', () {
      final result = SapsSmsParser.parse(
        'SAPS: Your licence collection notice for Ref 10470664 is ready.',
      );
      expect(result.statusMessage.toLowerCase(), contains('collection notice'));
      expect(result.statusStage, 3);
    });

    test('detects an approval notice', () {
      final result = SapsSmsParser.parse(
        'SAPS: Approval notice — Ref 10470664 has been approved.',
      );
      expect(result.statusMessage.toLowerCase(), contains('approval'));
      expect(result.statusStage, 3);
    });

    test('detects CFR processing', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 is now at the Central Firearms Registry for processing.',
      );
      expect(result.statusMessage, contains('CFR'));
      expect(result.statusStage, 2);
    });

    test('detects provincial processing', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 forwarded to Provincial Office.',
      );
      expect(result.statusMessage, contains('Provincial'));
      expect(result.statusStage, 1);
    });

    test('detects DFO receipt', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 application received at DFO.',
      );
      expect(result.statusMessage, contains('DFO'));
      expect(result.statusStage, 0);
    });

    test('returns empty status when none detected', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(result.statusMessage, '');
      expect(result.statusStage, isNull);
    });
  });

  group('SapsSmsParser.parse — application type inference', () {
    test('infers Section 16 dedicated hunting', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 dedicated hunting licence application approved.',
      );
      expect(
        result.applicationType,
        'Section 16 Dedicated Hunting',
      );
    });

    test('infers Section 13 self-defence', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 self-defence licence application received.',
      );
      expect(
        result.applicationType,
        'Section 13 – Licence to possess a firearm for self-defence',
      );
    });

    test('defaults to Competency Certificate', () {
      final result = SapsSmsParser.parse(
        'Ref 10470664 calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(result.applicationType, 'Competency Certificate');
    });
  });

  group('SapsSmsParser.parse — whitespace / case tolerance', () {
    test('normalizes non-breaking spaces', () {
      final result = SapsSmsParser.parse(
        'SAPS msg: Application Ref.\u00A010470664 for calibre\u00A06MM MUSGRAVE s/n OB14468',
      );
      expect(result.referenceNumber, '10470664');
      expect(result.calibre, '6MM MUSGRAVE');
      expect(result.serialNumber, 'OB14468');
    });

    test('is case-insensitive', () {
      final result = SapsSmsParser.parse(
        'saps msg: application ref. 10470664 for calibre 6mm musgrave s/n ob14468',
      );
      expect(result.referenceNumber, '10470664');
      expect(result.calibre, '6MM MUSGRAVE');
      expect(result.serialNumber, 'OB14468');
    });

    test('collapses multiple spaces', () {
      final result = SapsSmsParser.parse(
        'Ref   10470664   calibre   6MM  MUSGRAVE   s/n   OB14468',
      );
      expect(result.referenceNumber, '10470664');
      expect(result.calibre, '6MM MUSGRAVE');
      expect(result.serialNumber, 'OB14468');
    });
  });

  group('SapsSmsParseResult getters', () {
    test('hasReference / hasFirearmDetails / hasStatus reflect fields', () {
      final full = SapsSmsParser.parse(
        'SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(full.hasReference, isTrue);
      expect(full.hasFirearmDetails, isTrue);
      expect(full.hasStatus, isFalse);
      expect(full.hasAnyField, isTrue);

      final statusOnly = SapsSmsParser.parse(
        'Your licence collection notice for Ref 10470664 is ready.',
      );
      expect(statusOnly.hasReference, isTrue);
      expect(statusOnly.hasStatus, isTrue);
    });

    test('isEmpty is true for a blank parse', () {
      expect(SapsSmsParser.parse(null).isEmpty, isTrue);
    });
  });
}
