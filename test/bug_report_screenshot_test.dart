import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/feedback_firebase_service.dart';

/// Unit tests for the bug-report screenshot-attachment persistence contract.
///
/// `FeedbackFirebaseService` accepts an injectable `FirebaseFirestore`, so the
/// tests run against `fake_cloud_firestore` (no emulator / credentials needed).
/// `FirebaseAuth.instance.currentUser` is null in the test runner, so
/// `hunterId` resolves to `null` — that is expected and does not affect the
/// `screenshotUrls` persistence assertions under test.
void main() {
  late FakeFirebaseFirestore firestore;
  late FeedbackFirebaseService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FeedbackFirebaseService(
      firestore: firestore,
      currentUserIdResolver: () => 'test-user-uid',
    );
  });

  Future<Map<String, dynamic>?> _firstBugReport() async {
    final snap = await firestore.collection('bug_reports').get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }

  group('FeedbackFirebaseService.submitBugReport screenshots', () {
    test('persists screenshotUrls when attachments are provided', () async {
      const urls = [
        'https://firebasestorage.example.com/bug_report_attachments/u1/1.jpg',
        'https://firebasestorage.example.com/bug_report_attachments/u1/2.jpg',
      ];
      await service.submitBugReport(
        title: 'Crash on login',
        steps: '1. Open app\n2. Tap login',
        severity: 'Critical',
        screenshotUrls: urls,
      );

      final doc = await _firstBugReport();
      expect(doc, isNotNull);
      expect(doc!['title'], 'Crash on login');
      expect(doc['severity'], 'Critical');
      expect(doc['screenshotUrls'], urls);
    });

    test('omits screenshotUrls field entirely when no attachments', () async {
      await service.submitBugReport(
        title: 'Typo in dashboard',
        steps: 'See header label',
        severity: 'Low',
      );

      final doc = await _firstBugReport();
      expect(doc, isNotNull);
      // The field must be ABSENT (not an empty list) so legacy reports are
      // unaffected and downstream readers can distinguish "no screenshots"
      // from "screenshots failed to upload".
      expect(doc!.containsKey('screenshotUrls'), isFalse);
    });

    test('empty screenshotUrls list is treated as no attachments', () async {
      await service.submitBugReport(
        title: 'Minor glitch',
        steps: 'Flicker on theme toggle',
        severity: 'Medium',
        screenshotUrls: const [],
      );

      final doc = await _firstBugReport();
      expect(doc, isNotNull);
      expect(doc!.containsKey('screenshotUrls'), isFalse);
    });

    test('preserves a single screenshot url', () async {
      const url = 'https://firebasestorage.example.com/bug_report_attachments/u1/only.jpg';
      await service.submitBugReport(
        title: 'Single screenshot',
        steps: 'Repro steps',
        severity: 'Medium',
        screenshotUrls: const [url],
      );

      final doc = await _firstBugReport();
      expect(doc, isNotNull);
      expect(doc!['screenshotUrls'], [url]);
    });

    test('stamps the standard audit fields', () async {
      await service.submitBugReport(
        title: 't',
        steps: 's',
        severity: 'Low',
        screenshotUrls: const ['url'],
      );

      final doc = await _firstBugReport();
      expect(doc, isNotNull);
      expect(doc!['title'], 't');
      expect(doc['steps'], 's');
      expect(doc['severity'], 'Low');
      // hunterId is stubbed via the injected resolver in the test.
      expect(doc.containsKey('hunterId'), isTrue);
      expect(doc['hunterId'], 'test-user-uid');
      // fake_cloud_firestore resolves serverTimestamp() to a real Timestamp.
      expect(doc['timestamp'], isA<Timestamp>());
    });

    test('feature suggestion is unaffected (no screenshotUrls field)', () async {
      await service.submitFeatureSuggestion(
        title: 'Dark map mode',
        description: 'A night-friendly topo map palette',
        benefits: 'Less eye strain on night drives',
      );

      final snap = await firestore.collection('feature_suggestions').get();
      expect(snap.docs, hasLength(1));
      final doc = snap.docs.first.data();
      expect(doc.containsKey('screenshotUrls'), isFalse);
      expect(doc['title'], 'Dark map mode');
    });
  });
}
