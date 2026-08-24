import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/presentation/bug_report_modal.dart';
import 'package:jagspoor/features/hunter_mode/presentation/feature_suggestion_modal.dart';
import 'package:jagspoor/features/hunter_mode/services/feedback_firebase_service.dart';
import 'package:jagspoor/features/outfitter_mode/outfitter_dashboard.dart';
import 'package:jagspoor/features/support/services/support_email_composer.dart';

/// Outfitter Mode 'Report Bug' + 'Suggest New Feature' parity tests.
///
/// Verifies the shared Hunter/Outfitter feedback pipeline:
///  - [FeedbackFirebaseService] stamps the submitter uid, the originating
///    mode ('Outfitter'), device metadata (devicePlatform), and the content
///    into the SAME `bug_reports` / `feature_suggestions` Firestore
///    collections Hunter Mode uses.
///  - [SupportEmailComposer] tags the automated support email with the
///    originating mode + channel.
///  - The Outfitter dashboard exposes both access points and opens the SAME
///    modals Hunter Mode uses, pre-tagged with [FeedbackMode.outfitter].
void main() {
  late FakeFirebaseFirestore firestore;
  late FeedbackFirebaseService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FeedbackFirebaseService(
      firestore: firestore,
      currentUserIdResolver: () => 'outfitter-uid-1',
    );
  });

  Future<Map<String, dynamic>> firstDoc(String collection) async {
    final snap = await firestore.collection(collection).get();
    expect(snap.docs, hasLength(1));
    return snap.docs.first.data();
  }

  group('FeedbackMode constants', () {
    test('hunter + outfitter modes are distinct', () {
      expect(FeedbackMode.hunter, 'Hunter');
      expect(FeedbackMode.outfitter, 'Outfitter');
      expect(FeedbackMode.hunter, isNot(FeedbackMode.outfitter));
    });
  });

  group('FeedbackFirebaseService — outfitter bug report backend record', () {
    test('records uid, mode Outfitter, device metadata + content', () async {
      await service.submitBugReport(
        title: 'Booking dashboard blank',
        steps: '1. Open dashboard\n2. Tap Incoming Booking Requests',
        severity: 'Critical',
        mode: FeedbackMode.outfitter,
      );

      final doc = await firstDoc('bug_reports');
      expect(doc['title'], 'Booking dashboard blank');
      expect(doc['steps'], contains('Incoming Booking Requests'));
      expect(doc['severity'], 'Critical');
      expect(doc['hunterId'], 'outfitter-uid-1');
      expect(doc['mode'], 'Outfitter');
      expect(doc['devicePlatform'], isA<String>());
      expect((doc['devicePlatform'] as String).isNotEmpty, isTrue);
      expect(doc['timestamp'], isA<Timestamp>());
    });

    test('preserves screenshot attachments with the outfitter mode tag',
        () async {
      const urls = ['https://example.com/shot1.jpg'];
      await service.submitBugReport(
        title: 'Crash',
        steps: 'repro',
        severity: 'Low',
        screenshotUrls: urls,
        mode: FeedbackMode.outfitter,
      );

      final doc = await firstDoc('bug_reports');
      expect(doc['screenshotUrls'], urls);
      expect(doc['mode'], 'Outfitter');
    });

    test('hunter mode remains the default (back-compat)', () async {
      await service.submitBugReport(
        title: 't',
        steps: 's',
        severity: 'Medium',
      );

      final doc = await firstDoc('bug_reports');
      expect(doc['mode'], 'Hunter');
    });
  });

  group('FeedbackFirebaseService — outfitter feature suggestion record', () {
    test('records uid, mode Outfitter, device metadata + content', () async {
      await service.submitFeatureSuggestion(
        title: 'Bulk trophy import',
        description: 'CSV import for trophy stock rows',
        benefits: 'Faster farm onboarding',
        mode: FeedbackMode.outfitter,
      );

      final doc = await firstDoc('feature_suggestions');
      expect(doc['title'], 'Bulk trophy import');
      expect(doc['description'], 'CSV import for trophy stock rows');
      expect(doc['benefits'], 'Faster farm onboarding');
      expect(doc['hunterId'], 'outfitter-uid-1');
      expect(doc['mode'], 'Outfitter');
      expect((doc['devicePlatform'] as String).isNotEmpty, isTrue);
      expect(doc['timestamp'], isA<Timestamp>());
    });

    test('hunter mode remains the default (back-compat)', () async {
      await service.submitFeatureSuggestion(
        title: 't',
        description: 'd',
        benefits: 'b',
      );

      final doc = await firstDoc('feature_suggestions');
      expect(doc['mode'], 'Hunter');
    });
  });

  group('SupportEmailComposer — outfitter mode tagging', () {
    test('bug report body tags the outfitter mode + channel', () {
      final body = SupportEmailComposer.buildBugReportEmailBody(
        userId: 'outfitter-uid-1',
        title: 'Booking list empty',
        steps: 'open bookings',
        severity: 'Medium',
        mode: FeedbackMode.outfitter,
      );

      expect(body, contains('Mode       : Outfitter'));
      expect(body, contains('Submitted via JagSpoor Outfitter Dashboard'));
      expect(body, contains('Channel       : outfitter_dashboard'));
      expect(body, contains('User ID    : outfitter-uid-1'));
    });

    test('bug report mailto carries the outfitter-tagged body', () {
      final uri = SupportEmailComposer.buildBugReportMailtoUri(
        userId: 'u',
        title: 't',
        steps: 's',
        severity: 'Low',
        mode: FeedbackMode.outfitter,
      );

      final str = uri.toString();
      expect(uri.scheme, 'mailto');
      expect(uri.path, SupportEmailComposer.supportEmail);
      expect(str, contains(Uri.encodeComponent('Mode       : Outfitter')));
    });

    test('feature suggestion body tags the outfitter mode + channel', () {
      final body = SupportEmailComposer.buildFeatureSuggestionEmailBody(
        userId: 'outfitter-uid-1',
        title: 'Bulk import',
        description: 'desc',
        benefits: 'benefit',
        mode: FeedbackMode.outfitter,
      );

      expect(body, contains('Mode       : Outfitter'));
      expect(body, contains('Submitted via JagSpoor Outfitter Dashboard'));
      expect(body, contains('Channel       : outfitter_dashboard'));
    });

    test('hunter mode remains the default channel + footer', () {
      final body = SupportEmailComposer.buildBugReportEmailBody(
        userId: 'u',
        title: 't',
        steps: 's',
        severity: 'Low',
      );

      expect(body, contains('Mode       : Hunter'));
      expect(body, contains('Submitted via JagSpoor Hunter Dashboard'));
      expect(body, contains('Channel       : hunter_dashboard'));
    });

    test('systemContextBlock accepts an explicit channel', () {
      final block =
          SupportEmailComposer.systemContextBlock(channel: 'outfitter_dashboard');
      expect(block, contains('Channel       : outfitter_dashboard'));
      // Device metadata fields are still present for both portals.
      expect(block, contains('Platform      :'));
      expect(block, contains('OS Version    :'));
      expect(block, contains('Locale        :'));
    });
  });

  group('Outfitter dashboard — feedback access points (widget)', () {
    Future<void> buildDashboard(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OutfitterDashboard(theme: ThemeController.instance),
        ),
      );
      await tester.pump();
    }

    Future<void> scrollToText(WidgetTester tester, String text) async {
      await tester.scrollUntilVisible(
        find.text(text),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
    }

    testWidgets('renders Report Bug + Suggest New Feature cards',
        (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Report Bug');
      expect(find.text('Report Bug'), findsOneWidget);
      await scrollToText(tester, 'Suggest New Feature');
      expect(find.text('Suggest New Feature'), findsOneWidget);
    });

    testWidgets('tapping Report Bug opens the shared modal tagged Outfitter',
        (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Report Bug');
      await tester.tap(find.text('Report Bug'));
      await tester.pumpAndSettle();

      final modal = tester.widget<BugReportModal>(find.byType(BugReportModal));
      expect(modal.mode, FeedbackMode.outfitter);
      expect(find.text('🪲 REPORT BUG'), findsOneWidget);
      expect(find.text('Submit Bug Report'), findsOneWidget);

      // Close the sheet so the test tears down cleanly.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'tapping Suggest New Feature opens the shared modal tagged Outfitter',
        (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Suggest New Feature');
      await tester.tap(find.text('Suggest New Feature'));
      await tester.pumpAndSettle();

      final modal = tester.widget<FeatureSuggestionModal>(
          find.byType(FeatureSuggestionModal));
      expect(modal.mode, FeedbackMode.outfitter);
      expect(find.text('💡 SUGGEST NEW FEATURE'), findsOneWidget);
      expect(find.text('Submit Feature Suggestion'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('bug modal validation blocks an empty submission',
        (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Report Bug');
      await tester.tap(find.text('Report Bug'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Submit Bug Report'));
      await tester.pump();
      await tester.tap(find.text('Submit Bug Report'));
      await tester.pump();

      // Validators fire; the modal stays open (no submission without input).
      expect(find.text('Please enter a bug title'), findsOneWidget);
      expect(
          find.text('Please describe the steps to reproduce'), findsOneWidget);
      expect(find.byType(BugReportModal), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('feature suggestion modal validation blocks empty submission',
        (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Suggest New Feature');
      await tester.tap(find.text('Suggest New Feature'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Submit Feature Suggestion'));
      await tester.pump();
      await tester.tap(find.text('Submit Feature Suggestion'));
      await tester.pump();

      expect(find.text('Please enter a feature title'), findsOneWidget);
      expect(
          find.text('Please provide a detailed description'), findsOneWidget);
      expect(find.text('Please describe the expected benefits'), findsOneWidget);
      expect(find.byType(FeatureSuggestionModal), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('filled bug form enables the submit action', (tester) async {
      await buildDashboard(tester);
      await scrollToText(tester, 'Report Bug');
      await tester.tap(find.text('Report Bug'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter a brief title for the bug'),
          'Outfitter booking list empty');
      await tester.enterText(
          find.widgetWithText(
              TextFormField, 'Describe the steps to reproduce this bug...'),
          '1. Open dashboard\n2. Tap Incoming Booking Requests');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Submit Bug Report'));
      expect(button.onPressed, isNotNull,
          reason: 'A valid form must keep the submit action enabled.');
      // Validation passes: no error text after re-validation on submit tap.
      await tester.ensureVisible(find.text('Submit Bug Report'));
      await tester.pump();
      await tester.tap(find.text('Submit Bug Report'));
      await tester.pump();
      expect(find.text('Please enter a bug title'), findsNothing);
      expect(find.text('Please describe the steps to reproduce'), findsNothing);

      // The submission will fail in the test env (no Firebase app); the
      // modal's catch surfaces a snackbar instead of crashing.
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
      await tester.pumpAndSettle();
    });
  });
}
