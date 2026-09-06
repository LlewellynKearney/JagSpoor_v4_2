import 'package:flutter_test/flutter_test.dart';
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
}
