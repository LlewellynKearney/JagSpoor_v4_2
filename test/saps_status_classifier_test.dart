import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_cfr_scraper_client.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_sms_parser.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_status_classifier.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';

void main() {
  group('SapsStatusClassifier.normalize', () {
    test('collapses whitespace runs + lowercases + trims punctuation', () {
      expect(
        SapsStatusClassifier.normalize('  Application   Received  at  DFO! '),
        'application received at dfo',
      );
    });

    test('handles NBSP and newlines', () {
      expect(
        SapsStatusClassifier.normalize('Approved\n\tby\u00A0CFR'),
        'approved by cfr',
      );
    });

    test('null / blank -> empty', () {
      expect(SapsStatusClassifier.normalize(null), '');
      expect(SapsStatusClassifier.normalize('   '), '');
    });
  });

  group('SapsStatusClassifier.classify - stage mapping', () {
    test('maps the real CFR enquiry phrases to the correct stage', () {
      // DFO stage
      expect(
        SapsStatusClassifier.classify('Application received at DFO'),
        kSapsStageDfo,
      );
      expect(
        SapsStatusClassifier.classify('Received at District Firearms Office'),
        kSapsStageDfo,
      );
      expect(SapsStatusClassifier.classify('Application captured'), kSapsStageDfo);
      expect(SapsStatusClassifier.classify('Submitted'), kSapsStageDfo);

      // Provincial stage (incl. the real "send to the Provincial DFO" wording)
      expect(
        SapsStatusClassifier.classify(
          'The application was send to the Provincial DFO by the DFO and being processed',
        ),
        kSapsStageProvincial,
      );
      expect(
        SapsStatusClassifier.classify('Sent to Provincial DFO'),
        kSapsStageProvincial,
      );
      expect(
        SapsStatusClassifier.classify('At Provincial Office'),
        kSapsStageProvincial,
      );
      expect(
        SapsStatusClassifier.classify('Under review at Provincial'),
        kSapsStageProvincial,
      );

      // CFR stage
      expect(
        SapsStatusClassifier.classify('For consideration by the Commissioner'),
        kSapsStageCfr,
      );
      expect(
        SapsStatusClassifier.classify('Received at the CFR'),
        kSapsStageCfr,
      );
      expect(
        SapsStatusClassifier.classify('Forwarded to Central Firearms Registry'),
        kSapsStageCfr,
      );
      expect(
        SapsStatusClassifier.classify('Received at Licensing Section'),
        kSapsStageCfr,
      );
      expect(SapsStatusClassifier.classify('CFR Processing'), kSapsStageCfr);

      // The live portal phrases for application 10654672: "IN PREPARATION
      // FOR CONSIDERATION" with the appended "No status available contact
      // the DFO" note must classify to CFR (stage 2), NOT DFO.
      expect(
        SapsStatusClassifier.classify('IN PREPARATION FOR CONSIDERATION'),
        kSapsStageCfr,
      );
      expect(
        SapsStatusClassifier.classify(
          'IN PREPARATION FOR CONSIDERATION – No status available contact '
          'the DFO',
        ),
        kSapsStageCfr,
      );
      expect(
        SapsStatusClassifier.classify('No status available contact the DFO'),
        kSapsStageCfr,
      );

      // Printed / final stage
      expect(
        SapsStatusClassifier.classify('Licence approved and printed'),
        kSapsStagePrinted,
      );
      expect(
        SapsStatusClassifier.classify('Ready for Collection'),
        kSapsStagePrinted,
      );
      expect(SapsStatusClassifier.classify('Approved'), kSapsStagePrinted);
      expect(SapsStatusClassifier.classify('Printed'), kSapsStagePrinted);

      // Not found / error stage
      expect(
        SapsStatusClassifier.classify('Application not found in system'),
        kSapsStageNotFound,
      );
      expect(
        SapsStatusClassifier.classify('No record found'),
        kSapsStageNotFound,
      );
      expect(
        SapsStatusClassifier.classify('Facility not operational'),
        kSapsStageNotFound,
      );
    });

    test('longest-match-wins: a specific phrase beats a shorter keyword', () {
      // "sent to the provincial dfo" must win over the generic "sent" (which
      // is not even in the table) AND over "received" (DFO stage) because the
      // provincial phrase is longer.
      expect(
        SapsStatusClassifier.classify('Sent to the Provincial DFO'),
        kSapsStageProvincial,
      );
      // "for consideration by the commissioner" (CFR) beats "consideration"
      // and the generic "approved" would only match if present.
      expect(
        SapsStatusClassifier.classify(
          'For consideration by the Commissioner',
        ),
        kSapsStageCfr,
      );
      // "ready for collection" (Printed) beats the generic "ready".
      expect(
        SapsStatusClassifier.classify('Ready for Collection'),
        kSapsStagePrinted,
      );
    });

    test('null / blank / unrecognized default to DFO (safe default)', () {
      expect(SapsStatusClassifier.classify(null), kSapsStageDfo);
      expect(SapsStatusClassifier.classify(''), kSapsStageDfo);
      expect(SapsStatusClassifier.classify('   '), kSapsStageDfo);
      expect(
        SapsStatusClassifier.classify('Some Random Status XYZ'),
        kSapsStageDfo,
      );
    });
  });

  group('SapsStatusClassifier.displayLabel', () {
    test('maps each stage to a friendly label', () {
      expect(
        SapsStatusClassifier.displayLabel('Application received at DFO'),
        'Submitted to DFO',
      );
      expect(
        SapsStatusClassifier.displayLabel('At Provincial Office'),
        'At Provincial Office',
      );
      expect(
        SapsStatusClassifier.displayLabel('CFR Processing'),
        'At Central Registry',
      );
      expect(
        SapsStatusClassifier.displayLabel('Ready for Collection'),
        'Ready for Collection',
      );
      expect(
        SapsStatusClassifier.displayLabel('Not found in system'),
        'Status Unavailable',
      );
      expect(SapsStatusClassifier.displayLabel(null), 'Pending Review');
    });
  });

  group('SapsStatusClassifier.isApproved (Add to Safe trigger)', () {
    test('true for approved / finalised / printed phrases', () {
      expect(SapsStatusClassifier.isApproved('Approved'), isTrue);
      expect(SapsStatusClassifier.isApproved('Licence approved and printed'),
          isTrue);
      expect(SapsStatusClassifier.isApproved('Ready for Collection'), isTrue);
      expect(SapsStatusClassifier.isApproved('Card printed'), isTrue);
      expect(SapsStatusClassifier.isApproved('Application finalised'), isTrue);
      expect(SapsStatusClassifier.isApproved('Licence collected'), isTrue);
    });

    test('false for in-progress stages (CFR consideration is NOT approved)',
        () {
      expect(
        SapsStatusClassifier.isApproved(
          'For consideration by the Commissioner',
        ),
        isFalse,
      );
      expect(SapsStatusClassifier.isApproved('CFR Processing'), isFalse);
      expect(
        SapsStatusClassifier.isApproved('Application received at DFO'),
        isFalse,
      );
      expect(SapsStatusClassifier.isApproved('At Provincial Office'), isFalse);
      expect(SapsStatusClassifier.isApproved('Not found in system'), isFalse);
    });

    test('false for null / blank', () {
      expect(SapsStatusClassifier.isApproved(null), isFalse);
      expect(SapsStatusClassifier.isApproved('   '), isFalse);
    });

    test('the live 10654672 CFR phrase is NOT approved', () {
      // The real portal phrase from the verification run (stage 2).
      expect(
        SapsStatusClassifier.isApproved(
          'Received at Licensing Section — For consideration by the '
          'Commissioner',
        ),
        isFalse,
      );
    });
  });

  group('SapsStatusClassifier.nextStepForStage', () {
    test('maps each stage to the next workflow step', () {
      expect(SapsStatusClassifier.nextStepForStage(kSapsStageDfo), 'Provincial');
      expect(SapsStatusClassifier.nextStepForStage(kSapsStageProvincial), 'CFR');
      // Stage 2 (CFR) -> printed / collection (NOT "Provincial").
      expect(
        SapsStatusClassifier.nextStepForStage(kSapsStageCfr),
        'Printed / Ready for Collection',
      );
      expect(
        SapsStatusClassifier.nextStepForStage(kSapsStagePrinted),
        'Licence Collected',
      );
    });

    test('returns Status Unavailable for sentinel / unknown stages', () {
      expect(
        SapsStatusClassifier.nextStepForStage(kSapsStageNotFound),
        'Status Unavailable',
      );
      expect(
        SapsStatusClassifier.nextStepForStage(kSapsStageNeedSerialAndRef),
        'Status Unavailable',
      );
    });
  });

  group('SapsStatusClassifier.normalizeSerial', () {
    test('upper-cases and strips whitespace', () {
      expect(SapsStatusClassifier.normalizeSerial(' f004574 '), 'F004574');
      expect(SapsStatusClassifier.normalizeSerial('F0004574'), 'F0004574');
      expect(SapsStatusClassifier.normalizeSerial('ob 14 46 8'), 'OB14468');
    });

    test('null / blank -> empty', () {
      expect(SapsStatusClassifier.normalizeSerial(null), '');
      expect(SapsStatusClassifier.normalizeSerial('   '), '');
    });
  });

  group('SapsTrackerService delegation (legacy API preserved)', () {
    test('convertRawStatusToStage delegates to the classifier', () {
      expect(
        SapsTrackerService.convertRawStatusToStage('Submitted to Provincial'),
        1,
      );
      expect(
        SapsTrackerService.convertRawStatusToStage('CFR Processing'),
        2,
      );
      expect(
        SapsTrackerService.convertRawStatusToStage('Application received at DFO'),
        0,
      );
      expect(SapsTrackerService.convertRawStatusToStage('Not Found'), -1);
      expect(SapsTrackerService.convertRawStatusToStage(null), 0);
    });

    test('convertRawStatusToDisplay delegates to the classifier', () {
      expect(
        SapsTrackerService.convertRawStatusToDisplay('Provincial Office'),
        'At Provincial Office',
      );
      expect(
        SapsTrackerService.convertRawStatusToDisplay('Not Found'),
        'Status Unavailable',
      );
    });
  });

  group('SapsSmsParser uses SapsStatusClassifier (single source of truth)', () {
    test('status stage matches the classifier for the detected phrase', () {
      const samples = <String, String>{
        'Ref 10470664 application received at DFO.':
            'Application received at DFO',
        'Ref 10470664 forwarded to Provincial Office.': 'Submitted to Provincial',
        'Ref 10470664 is now at the Central Firearms Registry.':
            'Central Firearms Registry',
        'SAPS: Your licence collection notice for Ref 10470664 is ready.':
            'Ready for collection',
      };
      samples.forEach((message, phrase) {
        final parsed = SapsSmsParser.parse(message);
        expect(
          parsed.statusStage,
          SapsStatusClassifier.classify(phrase),
          reason: 'stage for "$message"',
        );
      });
    });

    test('matchedStatusPattern is the classifier display label', () {
      final parsed = SapsSmsParser.parse(
        'Ref 10470664 application received at DFO.',
      );
      expect(
        parsed.matchedStatusPattern,
        SapsStatusClassifier.displayLabel('Application received at DFO'),
      );
    });

    test('no detected status -> null stage (nothing to classify)', () {
      final parsed = SapsSmsParser.parse(
        'Ref 10470664 calibre 6MM MUSGRAVE s/n OB14468',
      );
      expect(parsed.statusStage, isNull);
      expect(parsed.matchedStatusPattern, isNull);
    });
  });

  group('SapsCfrScraperClient direct portal parsing', () {
    test('parses the results row + the updated-on notice', () {
      const html = '''
        <i>Take note: The data on this page were updated on <b>2026-10-10</b>.</i>
        <b>Search Results:</b>
        <table><thead><tr><th>Application Type</th><th>Application Number</th>
        <th>Calibre</th><th>Make</th><th>Serial Number</th><th>Status Date</th>
        <th>Status</th><th>Status Description</th><th>Next Step</th></tr></thead>
        <tr><td>Licence</td><td>10470664</td><td>6MM MUSGRAVE</td>
        <td>TIKKA</td><td>OB14468</td><td>2026-09-01</td>
        <td>Sent to Provincial DFO</td>
        <td>The application was send to the Provincial DFO by the DFO</td>
        <td>Await CFR</td></tr></table>
      ''';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      // Status + Status description are concatenated for the classifier.
      expect(
        status!.rawStatus,
        'Sent to Provincial DFO — The application was send to the Provincial '
        'DFO by the DFO',
      );
      expect(status.stage, kSapsStageProvincial);
      expect(status.displayLabel, 'At Provincial Office');
      expect(status.sapsUpdatedAt, DateTime.parse('2026-10-10'));
      expect(status.notFound, isFalse);
      expect(status.calibre, '6MM MUSGRAVE');
      expect(status.serialNumber, 'OB14468');
      expect(status.nextStep, 'Await CFR');
    });

    test('detects the NOT_FOUND response', () {
      const html = '''
        <i>The data on this page were updated on <b>2026-10-10</b>.</i>
        <table><tr><td colspan="9">No records to retrieve for your selected
        Reference Number (10470664) and Serial Number (OB14468) ...</td></tr>
        </table>
      ''';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      expect(status!.notFound, isTrue);
      expect(status.stage, kSapsStageNotFound);
      expect(status.displayLabel, 'Status Unavailable');
      expect(status.sapsUpdatedAt, DateTime.parse('2026-10-10'));
    });

    test('extracts the csrf form token + cookie + updated date', () {
      const html =
          '<input type="hidden" name="csrf" value="abc123">'
          '<i>were updated on <b>2026-10-10</b></i>';
      expect(SapsCfrScraperClient.extractCsrfField(html), 'abc123');
      expect(
        SapsCfrScraperClient.parseUpdatedDate(html),
        DateTime.parse('2026-10-10'),
      );
      expect(
        SapsCfrScraperClient.extractCsrfCookie(
          {'set-cookie': 'csrf_token=deadbeef; path=/; HttpOnly'},
        ),
        'deadbeef',
      );
      expect(SapsCfrScraperClient.extractCsrfCookie(const {}), isNull);
    });

    test('returns null for an empty / shapeless page', () {
      expect(SapsCfrScraperClient.parseEnquiryPage(''), isNull);
      expect(
        SapsCfrScraperClient.parseEnquiryPage('<html><body>nothing</body></html>'),
        isNull,
      );
    });
  });

  group('SAPS NEED_SERIAL_AND_REF + Search Results parsing', () {
    test('classifies the "Please supply a Serial Number AND Reference Number" '
        'prompt to the validation stage', () {
      expect(
        SapsStatusClassifier.classify(
          'Please supply a Serial Number AND Reference Number',
        ),
        kSapsStageNeedSerialAndRef,
      );
      expect(
        SapsStatusClassifier.classify(SapsCfrScraperClient.kNeedSerialAndRefStatus),
        kSapsStageNeedSerialAndRef,
      );
    });

    test('displayLabel for the validation prompt is the actionable hint', () {
      expect(
        SapsStatusClassifier.displayLabel(
          SapsCfrScraperClient.kNeedSerialAndRefStatus,
        ),
        'Enter both Serial + Reference for firearm apps '
        '(Ref only for competency)',
      );
    });

    test('parseEnquiryPage detects NEED_SERIAL_AND_REF + keeps the banner date',
        () {
      const html = '''
        <i>The data on this page were updated on <b>2026-10-10</b>.</i>
        <div class="error">Please supply a Serial Number AND Reference Number
        for a firearm application.</div>
      ''';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      expect(status!.rawStatus, SapsCfrScraperClient.kNeedSerialAndRefStatus);
      expect(status.stage, kSapsStageNeedSerialAndRef);
      expect(status.notFound, isFalse);
      expect(status.sapsUpdatedAt, DateTime.parse('2026-10-10'));
      expect(status.htmlSnippet, isNotEmpty);
    });

    test('parseEnquiryPage parses the 10-column Search Results row and '
        'concatenates Status + Status description', () {
      const html = '''
        <i>The data on this page were updated on <b>2026-10-10</b>.</i>
        <h3>Search Results:</h3>
        <table>
          <tr><th>Type</th><th>App No</th><th>ID</th><th>Caliber</th>
              <th>Make</th><th>Serial</th><th>Date</th><th>Status</th>
              <th>Status description</th><th>Next step</th></tr>
          <tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>
              <td>9001015009087</td><td>6MM MUSGRAVE</td><td>TIKKA T3X</td>
              <td>OB14468</td><td>2026-10-01</td><td>Received at Licensing
              Section</td><td>For consideration by the Commissioner</td>
              <td>Await decision</td></tr>
        </table>
      ''';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      // Status + Status description concatenated for the classifier.
      expect(status!.rawStatus, contains('Received at Licensing Section'));
      expect(status.rawStatus, contains('For consideration by the Commissioner'));
      expect(status.applicationType, 'Section 16 Dedicated Hunting');
      expect(status.applicationNumber, '10654672');
      expect(status.calibre, '6MM MUSGRAVE');
      expect(status.make, 'TIKKA T3X');
      expect(status.serialNumber, 'OB14468');
      expect(status.statusDate, '2026-10-01');
      expect(status.nextStep, 'Await decision');
      // CFR stage from the Licensing Section phrase.
      expect(status.stage, kSapsStageCfr);
    });

    test('parseEnquiryPage still parses the legacy 8-column layout', () {
      const html = '''
        <h3>Search Results:</h3>
        <table>
          <tr><td>Competency Certificate</td><td>10470664</td>
              <td>9mm</td><td>GLOCK</td><td>ABC123</td><td>2026-09-01</td>
              <td>Approved</td><td>Ready for collection</td>
              <td>Collect at DFO</td></tr>
        </table>
      ''';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      expect(status!.applicationType, 'Competency Certificate');
      expect(status.calibre, '9mm');
      expect(status.make, 'GLOCK');
      expect(status.serialNumber, 'ABC123');
      expect(status.stage, kSapsStagePrinted);
    });

    test('htmlSnippetOf collapses whitespace and truncates to 500 chars', () {
      final long = '<div>${'x' * 900}</div>';
      final snippet = SapsCfrScraperClient.htmlSnippetOf(long);
      expect(snippet.length, SapsCfrScraperClient.kHtmlSnippetMaxChars);
      expect(
        SapsCfrScraperClient.htmlSnippetOf('  a \n  b  '),
        'a b',
      );
    });

    test('buildQueryEnquiryUri emits the portal query parameters', () {
      final uri = SapsCfrScraperClient.buildQueryEnquiryUri(
        referenceNumber: '10654672',
        serialNumber: 'OB14468',
      );
      expect(uri.queryParameters['fsref'], '10654672');
      expect(uri.queryParameters['fref'], '10654672');
      expect(uri.queryParameters['fserial'], 'OB14468');
      expect(uri.queryParameters['fiserial'], 'OB14468');
      expect(uri.queryParameters.containsKey('fid'), isTrue);
      expect(uri.queryParameters.containsKey('frid'), isTrue);
      expect(uri.host, 'www.saps.gov.za');
    });
  });
}
