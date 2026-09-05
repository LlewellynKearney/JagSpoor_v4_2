import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';
import 'package:jagspoor/features/ballistics/data/models/saps_application_model.dart';

void main() {
  group('SapsTrackerService Status Conversion Tests', () {
    group('convertRawStatusToStage', () {
      test('should return 0 (Submitted/DFO) for "submitted" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Submitted');
        assert(result == 0, 'Expected 0 for Submitted, got $result');
      });

      test('should return 0 (Submitted/DFO) for "received at DFO" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Received at DFO');
        assert(result == 0, 'Expected 0 for Received at DFO, got $result');
      });

      test('should return 0 (Submitted/DFO) for "application received" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Application Received');
        assert(result == 0, 'Expected 0 for Application Received, got $result');
      });

      test('should return 1 (Provincial) for "provincial office" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Provincial Office');
        assert(result == 1, 'Expected 1 for Provincial Office, got $result');
      });

      test('should return 1 (Provincial) for "at Provincial" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('At Provincial');
        assert(result == 1, 'Expected 1 for At Provincial, got $result');
      });

      test('should return 1 (Provincial) for "submitted to provincial" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Submitted to Provincial');
        assert(result == 1, 'Expected 1 for Submitted to Provincial, got $result');
      });

      test('should return 2 (CFR) for "CFR" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('CFR Processing');
        assert(result == 2, 'Expected 2 for CFR, got $result');
      });

      test('should return 2 (CFR) for "central firearms registry" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Central Firearms Registry');
        assert(result == 2, 'Expected 2 for Central Firearms Registry, got $result');
      });

      test('should return 2 (CFR) for "at registry" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('At Registry');
        assert(result == 2, 'Expected 2 for At Registry, got $result');
      });

      test('should return 3 (Printed) for "printed" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Printed');
        assert(result == 3, 'Expected 3 for Printed, got $result');
      });

      test('should return 3 (Printed) for "ready for collection" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Ready for Collection');
        assert(result == 3, 'Expected 3 for Ready for Collection, got $result');
      });

      test('should return 3 (Printed) for "approved" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Approved');
        assert(result == 3, 'Expected 3 for Approved, got $result');
      });

      test('should return 3 (Printed) for "completed" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Completed');
        assert(result == 3, 'Expected 3 for Completed, got $result');
      });

      test('should return -1 (Not Found) for "not found" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Not Found');
        assert(result == -1, 'Expected -1 for Not Found, got $result');
      });

      test('should return -1 (Not Found) for "no record" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('No Record');
        assert(result == -1, 'Expected -1 for No Record, got $result');
      });

      test('should return -1 (Not Found) for "invalid" status', () {
        final result = SapsTrackerService.convertRawStatusToStage('Invalid Application');
        assert(result == -1, 'Expected -1 for Invalid, got $result');
      });
    });

    group('convertRawStatusToStage - Null Safety', () {
      test('should return 0 (default) for null input without crash', () {
        String? nullStatus;
        final result = SapsTrackerService.convertRawStatusToStage(nullStatus);
        assert(result == 0, 'Expected 0 (default) for null, got $result');
      });

      test('should return 0 (default) for empty string without crash', () {
        final result = SapsTrackerService.convertRawStatusToStage('');
        assert(result == 0, 'Expected 0 (default) for empty string, got $result');
      });

      test('should return 0 (default) for whitespace-only string without crash', () {
        final result = SapsTrackerService.convertRawStatusToStage('   ');
        assert(result == 0, 'Expected 0 (default) for whitespace, got $result');
      });

      test('should return 0 (default) for unrecognized status without crash', () {
        final result = SapsTrackerService.convertRawStatusToStage('Some Random Status XYZ');
        assert(result == 0, 'Expected 0 (default) for unrecognized, got $result');
      });
    });

    group('convertRawStatusToDisplay', () {
      test('should return "Pending Review" for null input without crash', () {
        String? nullStatus;
        final result = SapsTrackerService.convertRawStatusToDisplay(nullStatus);
        assert(result == 'Pending Review', 'Expected "Pending Review" for null, got "$result"');
      });

      test('should return "Pending Review" for empty string without crash', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('');
        assert(result == 'Pending Review', 'Expected "Pending Review" for empty, got "$result"');
      });

      test('should return "Submitted to DFO" for submitted status', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('Application Received');
        assert(result == 'Submitted to DFO', 'Expected "Submitted to DFO", got "$result"');
      });

      test('should return "At Provincial Office" for provincial status', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('Provincial Office');
        assert(result == 'At Provincial Office', 'Expected "At Provincial Office", got "$result"');
      });

      test('should return "At Central Registry" for CFR status', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('CFR Processing');
        assert(result == 'At Central Registry', 'Expected "At Central Registry", got "$result"');
      });

      test('should return "Ready for Collection" for printed status', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('Printed');
        assert(result == 'Ready for Collection', 'Expected "Ready for Collection", got "$result"');
      });

      test('should return "Status Unavailable" for not found status', () {
        final result = SapsTrackerService.convertRawStatusToDisplay('Not Found');
        assert(result == 'Status Unavailable', 'Expected "Status Unavailable", got "$result"');
      });
    });
  });

  group('SapsApplication Model Tests', () {
    test('should return correct stage index for DFO status', () {
      final app = SapsApplication(
        id: 'test-1',
        hunterId: 'user-1',
        referenceNumber: 'REF-001',
        idNumber: '1234567890123',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        lastChecked: DateTime.now(),
      );
      assert(app.stageIndex == 0, 'Expected stageIndex 0 for Submitted, got ${app.stageIndex}');
    });

    test('should return correct stage index for Provincial status', () {
      final app = SapsApplication(
        id: 'test-2',
        hunterId: 'user-1',
        referenceNumber: 'REF-002',
        idNumber: '1234567890123',
        applicationType: 'Section 15 Occasional Sport',
        currentStatus: 'Provincial',
        lastChecked: DateTime.now(),
      );
      assert(app.stageIndex == 1, 'Expected stageIndex 1 for Provincial, got ${app.stageIndex}');
    });

    test('should return correct stage index for CFR status', () {
      final app = SapsApplication(
        id: 'test-3',
        hunterId: 'user-1',
        referenceNumber: 'REF-003',
        idNumber: '1234567890123',
        applicationType: 'Section 16 Dedicated Hunting',
        currentStatus: 'CFR',
        lastChecked: DateTime.now(),
      );
      assert(app.stageIndex == 2, 'Expected stageIndex 2 for CFR, got ${app.stageIndex}');
    });

    test('should return correct stage index for Printed status', () {
      final app = SapsApplication(
        id: 'test-4',
        hunterId: 'user-1',
        referenceNumber: 'REF-004',
        idNumber: '1234567890123',
        applicationType: 'Competency Certificate',
        currentStatus: 'Printed',
        lastChecked: DateTime.now(),
      );
      assert(app.stageIndex == 3, 'Expected stageIndex 3 for Printed, got ${app.stageIndex}');
    });

    test('should return correct stage index for "ready_for_collection" status', () {
      final app = SapsApplication(
        id: 'test-5',
        hunterId: 'user-1',
        referenceNumber: 'REF-005',
        idNumber: '1234567890123',
        applicationType: 'Competency Certificate',
        currentStatus: 'ready_for_collection',
        lastChecked: DateTime.now(),
      );
      assert(app.stageIndex == 3, 'Expected stageIndex 3 for ready_for_collection, got ${app.stageIndex}');
    });

    test('should handle fromJson with missing fields gracefully', () {
      final json = <String, dynamic>{};
      final app = SapsApplication.fromJson(json);
      
      assert(app.id.isEmpty, 'Expected empty id');
      assert(app.hunterId.isEmpty, 'Expected empty hunterId');
      assert(app.referenceNumber.isEmpty, 'Expected empty referenceNumber');
      assert(app.idNumber.isEmpty, 'Expected empty idNumber');
      assert(app.applicationType == 'Competency Certificate', 'Expected default applicationType');
      assert(app.currentStatus == 'Pending', 'Expected default currentStatus');
    });

    test('should handle fromJson with null values gracefully', () {
      final json = <String, dynamic>{
        'id': null,
        'hunterId': null,
        'referenceNumber': null,
        'idNumber': null,
        'applicationType': null,
        'currentStatus': null,
        'lastChecked': null,
      };
      final app = SapsApplication.fromJson(json);
      
      assert(app.id.isEmpty, 'Expected empty id for null');
      assert(app.applicationType == 'Competency Certificate', 'Expected default applicationType for null');
      assert(app.currentStatus == 'Pending', 'Expected default currentStatus for null');
    });

    test('should handle toFirestore and back without data loss', () {
      final original = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Section 16 Dedicated Hunting',
        currentStatus: 'Provincial',
        lastChecked: DateTime(2024, 7, 15, 10, 30),
      );

      final json = original.toFirestore();
      final restored = SapsApplication.fromJson(json, id: original.id);

      assert(restored.id == original.id, 'id mismatch');
      assert(restored.hunterId == original.hunterId, 'hunterId mismatch');
      assert(restored.referenceNumber == original.referenceNumber, 'referenceNumber mismatch');
      assert(restored.idNumber == original.idNumber, 'idNumber mismatch');
      assert(restored.applicationType == original.applicationType, 'applicationType mismatch');
      assert(restored.currentStatus == original.currentStatus, 'currentStatus mismatch');
    });

    test('should round-trip the provincial DFO milestone through JSON', () {
      final original = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Section 16 Dedicated Hunting',
        currentStatus: 'Provincial',
        submittedAt: DateTime(2024, 6, 3),
        provincialDfoReceivedAt: DateTime(2024, 7, 15),
        lastChecked: DateTime(2024, 7, 15, 10, 30),
      );

      final restored = SapsApplication.fromJson(original.toFirestore(),
          id: original.id);

      assert(restored.submittedAt == original.submittedAt,
          'submittedAt mismatch');
      assert(restored.provincialDfoReceivedAt == original.provincialDfoReceivedAt,
          'provincialDfoReceivedAt mismatch');
    });

    test('should tolerate the dfoReceivedAt alias for the provincial milestone',
        () {
      final restored = SapsApplication.fromJson({
        'id': 'x',
        'hunterId': 'h',
        'referenceNumber': 'r',
        'idNumber': 'i',
        'applicationType': 'Competency Certificate',
        'currentStatus': 'Provincial',
        'dfoReceivedAt': '2024-07-15T00:00:00.000',
        'lastChecked': '2024-07-15T10:30:00.000',
      });

      assert(restored.provincialDfoReceivedAt == DateTime(2024, 7, 15),
          'dfoReceivedAt alias not resolved');
    });

    test('should compute working days since the submitted milestone', () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        submittedAt: DateTime(2026, 9, 7), // Monday
        lastChecked: DateTime(2026, 9, 11),
      );

      // Mon 7 Sep -> Fri 11 Sep 2026 = 5 working days (incl. submission day).
      assert(app.workingDaysSinceSubmitted(DateTime(2026, 9, 11)) == 5,
          'Expected 5 working days since submission');
    });

    test('should compute working days since the provincial DFO milestone', () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Section 16 Dedicated Hunting',
        currentStatus: 'Provincial',
        provincialDfoReceivedAt: DateTime(2026, 9, 7), // Monday
        lastChecked: DateTime(2026, 9, 11),
      );

      assert(app.workingDaysSinceProvincialDfo(DateTime(2026, 9, 11)) == 5,
          'Expected 5 working days since provincial DFO');
    });

    test('should return null working days when a milestone is unknown', () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        lastChecked: DateTime(2026, 9, 11),
      );

      assert(app.workingDaysSinceSubmitted(DateTime(2026, 9, 11)) == null,
          'Expected null without a submission date');
      assert(app.workingDaysSinceProvincialDfo(DateTime(2026, 9, 11)) == null,
          'Expected null without a provincial DFO date');
    });

    test('should return null working days when a milestone is in the future',
        () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        submittedAt: DateTime(2026, 9, 14),
        lastChecked: DateTime(2026, 9, 11),
      );

      assert(app.workingDaysSinceSubmitted(DateTime(2026, 9, 11)) == null,
          'Expected null for a future submission date');
    });

    test('should fall back to createdAt when submittedAt is missing', () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        createdAt: DateTime(2026, 9, 7), // Monday
        lastChecked: DateTime(2026, 9, 11),
      );

      assert(app.submittedAt == null, 'Expected no official submission date');
      assert(app.effectiveSubmissionDate == DateTime(2026, 9, 7),
          'Expected createdAt to be the effective submission date');
      assert(app.workingDaysSinceSubmitted(DateTime(2026, 9, 11)) == 5,
          'Expected 5 working days via the createdAt fallback');
    });

    test('should prefer submittedAt over createdAt for the effective date',
        () {
      final app = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        submittedAt: DateTime(2026, 9, 7), // Monday
        createdAt: DateTime(2026, 9, 1),
        lastChecked: DateTime(2026, 9, 11),
      );

      assert(app.effectiveSubmissionDate == DateTime(2026, 9, 7),
          'Expected submittedAt to win over createdAt');
      assert(app.workingDaysSinceSubmitted(DateTime(2026, 9, 11)) == 5,
          'Expected 5 working days from the official submission date');
    });

    test('should round-trip the createdAt fallback through JSON', () {
      final original = SapsApplication(
        id: 'test-id',
        hunterId: 'hunter-123',
        referenceNumber: 'SAPS-2024-12345',
        idNumber: '9001015009087',
        applicationType: 'Competency Certificate',
        currentStatus: 'Submitted',
        createdAt: DateTime(2026, 9, 7),
        lastChecked: DateTime(2026, 9, 11),
      );

      final restored = SapsApplication.fromJson(original.toFirestore(),
          id: original.id);
      assert(restored.createdAt == original.createdAt,
          'createdAt mismatch after round-trip');
      assert(restored.effectiveSubmissionDate == original.createdAt,
          'effectiveSubmissionDate should resolve from createdAt');
    });

    test('should tolerate the created_at snake_case alias', () {
      final restored = SapsApplication.fromJson({
        'id': 'x',
        'hunterId': 'h',
        'referenceNumber': 'r',
        'idNumber': 'i',
        'applicationType': 'Competency Certificate',
        'currentStatus': 'Submitted',
        'created_at': '2026-09-07T00:00:00.000',
        'lastChecked': '2026-09-11T10:30:00.000',
      });
      assert(restored.createdAt == DateTime(2026, 9, 7),
          'created_at alias not resolved');
    });

    test('should expose the next anticipated status label', () {
      SapsApplication app(String status) => SapsApplication(
            id: 'x',
            hunterId: 'h',
            referenceNumber: 'r',
            idNumber: 'i',
            applicationType: 'Competency Certificate',
            currentStatus: status,
            lastChecked: DateTime(2026, 9, 11),
          );

      assert(app('Submitted').nextStatusLabel == 'Provincial',
          'DFO -> Provincial expected');
      assert(app('Provincial').nextStatusLabel == 'CFR',
          'Provincial -> CFR expected');
      assert(app('CFR').nextStatusLabel == 'Printed / Ready for Collection',
          'CFR -> Printed expected');
      assert(app('Printed').nextStatusLabel == 'Licence Collected',
          'Printed -> Collected expected');
      assert(app('ready_for_collection').nextStatusLabel == 'Licence Collected',
          'ready_for_collection -> Collected expected');
      // Tolerant substring matching so realistic scraper status strings
      // resolve correctly too.
      assert(app('Application received at DFO').nextStatusLabel == 'Provincial',
          'DFO substring -> Provincial expected');
      assert(app('Under review at Provincial').nextStatusLabel == 'CFR',
          'Provincial substring -> CFR expected');
      assert(app('CFR Processing').nextStatusLabel ==
          'Printed / Ready for Collection',
          'CFR substring -> Printed expected');
      assert(app('Licence approved and printed').nextStatusLabel ==
          'Licence Collected',
          'printed substring -> Collected expected');
    });

    test('should expose a plain-language current status description', () {
      SapsApplication app(String status) => SapsApplication(
            id: 'x',
            hunterId: 'h',
            referenceNumber: 'r',
            idNumber: 'i',
            applicationType: 'Competency Certificate',
            currentStatus: status,
            lastChecked: DateTime(2026, 9, 11),
          );

      expect(app('Submitted').currentStatusDescription,
          contains('District Firearms Office'));
      expect(app('Provincial').currentStatusDescription,
          contains('Provincial Firearms Office'));
      expect(app('CFR').currentStatusDescription,
          contains('Central Firearms Registry'));
      expect(app('Printed').currentStatusDescription, contains('printed'));
      expect(app('Unknown status').currentStatusDescription,
          contains('progressing'));
      // Tolerant substring matching for realistic scraper status strings.
      expect(app('Application received at DFO').currentStatusDescription,
          contains('District Firearms Office'));
      expect(app('Under review at Provincial').currentStatusDescription,
          contains('Provincial Firearms Office'));
      expect(app('CFR Processing').currentStatusDescription,
          contains('Central Firearms Registry'));
      expect(app('Licence approved and printed').currentStatusDescription,
          contains('printed'));
    });

    test('should expose a stage-appropriate waiting estimate', () {
      SapsApplication app(String status) => SapsApplication(
            id: 'x',
            hunterId: 'h',
            referenceNumber: 'r',
            idNumber: 'i',
            applicationType: 'Competency Certificate',
            currentStatus: status,
            lastChecked: DateTime(2026, 9, 11),
          );

      expect(app('Submitted').currentStatusEstimate, contains('DFO'));
      expect(app('Provincial').currentStatusEstimate, contains('Provincial'));
      expect(app('CFR').currentStatusEstimate, contains('CFR'));
      expect(app('Printed').currentStatusEstimate, contains('Printing'));
    });
  });

  group('SapsScraperResult Tests', () {
    test('should parse from JSON correctly', () {
      final json = {
        'applicationId': 'app-123',
        'status': 'Printed',
        'statusCode': 3,
        'lastChecked': '2024-07-15T10:30:00.000Z',
        'success': true,
      };

      final result = SapsScraperResult.fromJson(json);
      assert(result.applicationId == 'app-123', 'applicationId mismatch');
      assert(result.status == 'Printed', 'status mismatch');
      assert(result.statusCode == 3, 'statusCode mismatch');
      assert(result.success == true, 'success mismatch');
      assert(result.lastChecked.year == 2024, 'lastChecked year mismatch');
    });

    test('should handle null values in JSON without crash', () {
      final json = <String, dynamic>{
        'applicationId': null,
        'status': null,
        'statusCode': null,
        'lastChecked': null,
        'success': null,
      };

      final result = SapsScraperResult.fromJson(json);
      assert(result.applicationId.isEmpty, 'Expected empty applicationId for null');
      assert(result.status.isEmpty, 'Expected empty status for null');
      assert(result.statusCode == 0, 'Expected 0 statusCode for null');
      assert(result.success == false, 'Expected false success for null');
    });

    test('should convert to JSON correctly', () {
      final result = SapsScraperResult(
        applicationId: 'app-456',
        status: 'CFR',
        statusCode: 2,
        lastChecked: DateTime(2024, 7, 15, 14, 0),
        success: true,
        error: null,
      );

      final json = result.toJson();
      assert(json['applicationId'] == 'app-456', 'applicationId mismatch');
      assert(json['status'] == 'CFR', 'status mismatch');
      assert(json['statusCode'] == 2, 'statusCode mismatch');
      assert(json['success'] == true, 'success mismatch');
      assert(json.containsKey('error') == false, 'Should not contain error key when null');
    });

    test('should include error in JSON when present', () {
      final result = SapsScraperResult(
        applicationId: 'app-789',
        status: '',
        statusCode: -1,
        lastChecked: DateTime.now(),
        success: false,
        error: 'Network timeout',
      );

      final json = result.toJson();
      assert(json['error'] == 'Network timeout', 'error mismatch');
    });
  });

  group('Stage Index Consistency Tests', () {
    test('should maintain consistent mapping between service and model', () {
      // Test that convertRawStatusToStage produces results that SapsApplication can use
      final testStatuses = [
        'Submitted',
        'Provincial',
        'CFR',
        'Printed',
      ];

      for (final status in testStatuses) {
        final stageFromService = SapsTrackerService.convertRawStatusToStage(status);
        final stageFromModel = SapsApplication(
          id: 'test',
          hunterId: 'test',
          referenceNumber: 'test',
          idNumber: 'test',
          applicationType: 'test',
          currentStatus: status,
          lastChecked: DateTime.now(),
        ).stageIndex;

        assert(stageFromService == stageFromModel, 
            'Stage mismatch for "$status": service=$stageFromService, model=$stageFromModel');
      }
    });

    test('should handle case-insensitive status matching', () {
      final variations = ['submitted', 'SUBMITTED', 'Submitted', 'SuBmItTeD'];
      for (final status in variations) {
        final result = SapsTrackerService.convertRawStatusToStage(status);
        assert(result == 0, 'Expected 0 for all variations of "submitted", got $result for "$status"');
      }
    });

    test('should handle partial matches in status strings', () {
      final partialStatuses = [
        'Status: Application received at DFO office',
        'Current: Received at District Firearms Officer',
        'Update: Provincial processing complete',
        'Stage: At Central Firearms Registry (CFR)',
        'Final: Ready for collection at police station',
      ];

      // These should all be recognized based on partial matching
      assert(SapsTrackerService.convertRawStatusToStage(partialStatuses[0]) == 0, 
          'Should recognize DFO in partial status');
      assert(SapsTrackerService.convertRawStatusToStage(partialStatuses[1]) == 0, 
          'Should recognize Received in partial status');
      assert(SapsTrackerService.convertRawStatusToStage(partialStatuses[2]) == 1, 
          'Should recognize Provincial in partial status');
      assert(SapsTrackerService.convertRawStatusToStage(partialStatuses[3]) == 2, 
          'Should recognize CFR in partial status');
      assert(SapsTrackerService.convertRawStatusToStage(partialStatuses[4]) == 3, 
          'Should recognize collection in partial status');
    });
  });
}
