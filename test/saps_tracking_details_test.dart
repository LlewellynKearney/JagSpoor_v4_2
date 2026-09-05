import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/saps_tracking_details.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';

void main() {
  // Construct the fake Firestore first so the `FieldValue` platform binds to
  // the mock before any production Timestamp/FieldValue is realised (same
  // pattern as `optic_log_service_test.dart`).
  FakeFirebaseFirestore();

  group('SapsStatusTimelineEntry', () {
    test('fromJson round-trips all fields', () {
      final entry = SapsStatusTimelineEntry.fromJson({
        'label': 'Submitted to DFO',
        'timestamp': '2026-08-01T09:30:00.000',
        'detail': 'Application received at the DFO.',
      });
      expect(entry.label, 'Submitted to DFO');
      expect(entry.timestamp, DateTime.parse('2026-08-01T09:30:00.000'));
      expect(entry.detail, 'Application received at the DFO.');

      final map = entry.toJson();
      expect(map['label'], 'Submitted to DFO');
      expect(map.containsKey('timestamp'), isTrue);
      expect(map.containsKey('detail'), isTrue);
    });

    test('tolerates missing details', () {
      final entry = SapsStatusTimelineEntry.fromJson({
        'label': 'Latest update',
      });
      expect(entry.timestamp, isNull);
      expect(entry.detail, isNull);
    });

    test('accepts a Firestore Timestamp', () {
      final ts = Timestamp.fromDate(DateTime(2026, 8, 5));
      final entry = SapsStatusTimelineEntry.fromJson({
        'label': 'CFR',
        'timestamp': ts,
      });
      expect(entry.timestamp, DateTime(2026, 8, 5));
    });
  });

  group('SapsWaitingEstimate && SapsBatchDetail', () {
    test('waiting estimate round-trips', () {
      final estimate = SapsWaitingEstimate.fromJson({
        'stageLabel': 'CFR processing',
        'estimate': 'Typically 8–16 weeks',
      });
      expect(estimate.stageLabel, 'CFR processing');
      expect(estimate.estimate, 'Typically 8–16 weeks');
      final map = estimate.toJson();
      expect(map['stageLabel'], 'CFR processing');
      expect(map['estimate'], 'Typically 8–16 weeks');
    });

    test('batch detail round-trips', () {
      final batch = SapsBatchDetail.fromJson({
        'batchNumber': 'B-2026-014',
        'submittedAt': '2026-08-01T10:00:00.000',
        'applicationCount': 12,
        'status': 'Sent to CFR',
      });
      expect(batch.batchNumber, 'B-2026-014');
      expect(batch.applicationCount, 12);
      expect(batch.status, 'Sent to CFR');
      expect(batch.submittedAt, DateTime.parse('2026-08-01T10:00:00.000'));

      final map = batch.toJson();
      expect(map['batchNumber'], 'B-2026-014');
      expect(map['applicationCount'], 12);
    });

    test('batch detail tolerates missing optional fields', () {
      final batch = SapsBatchDetail.fromJson({'batchNumber': 'B-1'});
      expect(batch.submittedAt, isNull);
      expect(batch.applicationCount, isNull);
      expect(batch.status, isNull);
    });
  });

  group('SapsTrackingDetailsFactory.fromApplicationFields', () {
    test('synthesizes a timeline from card fields', () {
      final details = SapsTrackingDetailsFactory.fromApplicationFields(
        applicationId: 'app-1',
        currentStatus: 'CFR',
        statusMessage: 'At Central Registry',
        submittedAt: DateTime(2026, 8, 1),
        statusUpdatedAt: DateTime(2026, 8, 10),
        batchNumber: 'B-2026-014',
        refreshedAt: DateTime(2026, 8, 11),
      );

      expect(details.applicationId, 'app-1');
      expect(details.timeline, hasLength(2));
      expect(details.timeline.first.label, 'Application submitted');
      expect(details.timeline.last.label, 'At Central Registry');
      expect(details.waitingEstimates, hasLength(4));
      expect(details.batches, hasLength(1));
      expect(details.batches.first.batchNumber, 'B-2026-014');
      expect(details.currentProgressLabel, 'At Central Registry');
      expect(details.refreshedAt, DateTime(2026, 8, 11));
    });

    test('builds empty timeline + batches for a blank application', () {
      final details = SapsTrackingDetailsFactory.fromApplicationFields(
        applicationId: 'app-2',
      );
      expect(details.timeline, isEmpty);
      expect(details.batches, isEmpty);
      expect(details.waitingEstimates, hasLength(4));
      expect(details.currentProgressLabel, isNull);
    });

    test('falls back to createdAt in the timeline when submittedAt is missing',
        () {
      final details = SapsTrackingDetailsFactory.fromApplicationFields(
        applicationId: 'app-3',
        currentStatus: 'Submitted',
        createdAt: DateTime(2026, 9, 7),
        batchNumber: 'B-3',
      );

      expect(details.timeline, hasLength(2));
      expect(details.timeline.first.label, 'Application record created');
      expect(details.timeline.first.timestamp, DateTime(2026, 9, 7));
      expect(details.batches.single.submittedAt, DateTime(2026, 9, 7));
    });

    test('prefers submittedAt over createdAt in the timeline', () {
      final details = SapsTrackingDetailsFactory.fromApplicationFields(
        applicationId: 'app-4',
        currentStatus: 'Submitted',
        submittedAt: DateTime(2026, 8, 1),
        createdAt: DateTime(2026, 8, 1).add(const Duration(days: 1)),
      );

      expect(details.timeline.first.label, 'Application submitted');
      expect(details.timeline.first.timestamp, DateTime(2026, 8, 1));
    });
  });

  group('SapsTrackingDetails.fromJson', () {
    test('parses a structured trackingDetails payload', () {
      final details = SapsTrackingDetails.fromJson({
        'timeline': [
          {'label': 'Submitted', 'timestamp': '2026-08-01T08:00:00.000'},
          {'label': 'CFR processing', 'timestamp': '2026-08-10T09:00:00.000'},
        ],
        'waitingEstimates': [
          {'stageLabel': 'CFR', 'estimate': '8–16 weeks'},
        ],
        'batches': [
          {'batchNumber': 'B-1', 'applicationCount': 20},
        ],
        'currentProgressLabel': 'CFR processing',
        'currentProgressDetail': 'With the Central Firearms Registry.',
        'refreshedAt': '2026-08-11T10:00:00.000',
      }, applicationId: 'app-3');

      expect(details.applicationId, 'app-3');
      expect(details.timeline, hasLength(2));
      expect(details.waitingEstimates, hasLength(1));
      expect(details.batches, hasLength(1));
      expect(details.currentProgressLabel, 'CFR processing');
      expect(details.refreshedAt, DateTime.parse('2026-08-11T10:00:00.000'));
    });

    test('round-trips through toJson with all data preserved', () {
      final details = SapsTrackingDetails(
        applicationId: 'app-4',
        timeline: const [
          SapsStatusTimelineEntry(
            label: 'Submitted',
            detail: 'At DFO',
          ),
        ],
        waitingEstimates: const [
          SapsWaitingEstimate(stageLabel: 'DFO', estimate: '2–4 weeks'),
        ],
        batches: const [
          SapsBatchDetail(
            batchNumber: 'B-9',
            applicationCount: 5,
            status: 'Sent',
          ),
        ],
        currentProgressLabel: 'CFR',
        refreshedAt: DateTime(2026, 8, 11),
      );

      final map = details.toJson();
      final restored = SapsTrackingDetails.fromJson(
        map,
        applicationId: 'app-4',
      );
      expect(restored.timeline, hasLength(1));
      expect(restored.timeline.first.label, 'Submitted');
      expect(restored.waitingEstimates.single.estimate, '2–4 weeks');
      expect(restored.batches.single.applicationCount, 5);
      expect(restored.currentProgressLabel, 'CFR');
    });
  });

  group('SapsTrackerService.fetchTrackingDetails', () {
    test('returns null for a missing application (never throws)', () async {
      final fake = FakeFirebaseFirestore();
      final service = SapsTrackerService.forTesting(fake);

      final details = await service.fetchTrackingDetails('does-not-exist');
      expect(details, isNull);
    });

    test('returns the stored structured trackingDetails', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('license_applications').doc('app-1').set({
        'hunterId': 'u1',
        'currentStatus': 'CFR',
        'trackingDetails': {
          'timeline': [
            {'label': 'Submitted', 'timestamp': '2026-08-01T08:00:00.000'},
          ],
          'waitingEstimates': [
            {'stageLabel': 'DFO', 'estimate': '2–4 weeks'},
          ],
          'batches': [
            {'batchNumber': 'B-2026-014', 'applicationCount': 12},
          ],
          'currentProgressLabel': 'CFR processing',
          'refreshedAt': '2026-08-11T10:00:00.000',
        },
      });
      final service = SapsTrackerService.forTesting(fake);

      final details = await service.fetchTrackingDetails('app-1');
      expect(details, isNotNull);
      expect(details!.timeline, hasLength(1));
      expect(details.waitingEstimates, hasLength(1));
      expect(details.batches.single.batchNumber, 'B-2026-014');
      expect(details.currentProgressLabel, 'CFR processing');
      expect(details.refreshedAt, DateTime.parse('2026-08-11T10:00:00.000'));
    });

    test(
        'synthesizes details from card fields when no trackingDetails stored',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('license_applications').doc('app-2').set({
        'hunterId': 'u1',
        'referenceNumber': '10470664',
        'currentStatus': 'CFR',
        'statusMessage': 'At Central Registry',
        'batchNumber': 'B-9',
        'submittedAt': '2026-08-01T09:00:00.000',
        'statusUpdatedAt': '2026-08-10T09:00:00.000',
      });
      final service = SapsTrackerService.forTesting(fake);

      final details = await service.fetchTrackingDetails('app-2');
      expect(details, isNotNull);
      expect(details!.timeline, isNotEmpty);
      expect(details.batches.single.batchNumber, 'B-9');
      expect(details.currentProgressLabel, 'At Central Registry');
    });
  });

  group(
    'SapsTrackerService.refreshApplication (per-application manual refresh)',
    () {
      test('refresh propagates a scraped status onto the application doc',
          () async {
        final fake = FakeFirebaseFirestore();
        await fake.collection('license_applications').doc('app-3').set({
          'hunterId': 'u1',
          'referenceNumber': '10470664',
        });
        final service = SapsTrackerService.forTesting(fake);

        final result = await service.refreshApplication('app-3');
        expect(result, isNotNull);
        expect(result.success, isTrue);
        expect(result.statusMessage, isNotNull);
        expect(result.statusMessage, isNotEmpty);

        final doc =
            await fake.collection('license_applications').doc('app-3').get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['currentStatus'], result.statusMessage);
        expect(doc.data()!['statusCode'], isA<int>());
        expect(doc.data()!['lastChecked'], isA<String>());
      });

      test('refresh application on a missing application returns a failure'
          ' result (never throws)', () async {
        final fake = FakeFirebaseFirestore();
        final service = SapsTrackerService.forTesting(fake);

        final result = await service.refreshApplication('does-not-exist');
        expect(result.success, isFalse);
        expect(result.message, isNotEmpty);
      });
    },
  );
}