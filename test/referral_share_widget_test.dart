import 'dart:math' as dart_math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';
import 'package:jagspoor/features/referral/widgets/referral_share_widget.dart';

/// Widget tests for the reusable "Refer & Earn" [ReferralShareWidget].
///
/// Exercises the card against a real `FakeFirebaseFirestore` (via the
/// injectable repository seam): auto-generate-or-load, the formatted code +
/// deep-link rendering, COPY LINK with visual confirmation (clipboard
/// stubbed via the platform method channel), and the WhatsApp intent
/// (url_launcher stubbed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FakeFirebaseFirestore();

  late FakeFirebaseFirestore firestore;
  late ReferralRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ReferralRepository.forTesting(
      firestore: firestore,
      currentUserIdResolver: () => 'uid-1',
      random: dart_math.Random(3),
    );
    // Stub the platform clipboard so the COPY LINK action resolves without a
    // native intent (the url_launcher channel is stubbed per-test where the
    // share button is exercised).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpCard(WidgetTester tester) async {
    final theme = ThemeController();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.lightTheme,
        home: Scaffold(
          body: ReferralShareWidget(theme: theme, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ReferralShareWidget', () {
    testWidgets('renders a loading row while the profile resolves',
        (tester) async {
      final theme = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.lightTheme,
          home: Scaffold(body: ReferralShareWidget(theme: theme, repository: repo)),
        ),
      );
      // The initial build frame shows the loading state before the async
      // profile resolution completes.
      expect(find.text('Refer & Earn'), findsOneWidget);
      expect(find.textContaining('Loading your referral code'),
          findsWidgets);
    });

    testWidgets('auto-generates a code and shows the formatted code + link',
        (tester) async {
      await pumpCard(tester);

      expect(find.text('Refer & Earn'), findsOneWidget);
      // The code is auto-generated (8 chars from the safe alphabet).
      final codeText = find.textContaining(RegExp(r'[A-Z2-9]{8}'));
      expect(codeText, findsWidgets);
      expect(find.text('COPY LINK'), findsOneWidget);
      expect(find.text('WHATSAPP'), findsOneWidget);
      expect(find.textContaining('jagspoor.page.link/referral?code='),
          findsOneWidget);
    });

    testWidgets('loads + displays an existing stored code', (tester) async {
      await firestore.collection('referral_profiles').doc('uid-1').set({
        'userId': 'uid-1',
        'referralCode': 'STORED123',
        'bankingDetailsProvided': false,
      });
      await pumpCard(tester);

      expect(find.text('STOR ED12 3'), findsOneWidget);
      expect(find.textContaining('code=STORED123'), findsOneWidget);
    });

    testWidgets('COPY LINK writes to the clipboard + shows confirmation',
        (tester) async {
      var copiedText = '';
      final binding = TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger;
      binding.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          final args = call.arguments;
          if (args is Map) {
            copiedText = (args['text'] as String?) ?? '';
          }
          return null;
        },
      );
      await pumpCard(tester);

      await tester.tap(find.text('COPY LINK'));
      await tester.pumpAndSettle();

      expect(copiedText, startsWith('https://jagspoor.page.link/referral?code='));
      expect(find.text('✓ Copied to clipboard'), findsOneWidget);
    });

    testWidgets('the WhatsApp button launches a wa.me intent', (tester) async {
      var launchedUrl = '';
      final binding = TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger;
      binding.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          final args = call.arguments;
          if (args is Map) {
            launchedUrl = (args['url'] as String?) ?? '';
          }
          return true;
        },
      );
      await pumpCard(tester);

      await tester.tap(find.text('WHATSAPP'));
      await tester.pumpAndSettle();

      expect(launchedUrl, startsWith('https://wa.me/?text='));
      // The deep link inside the message is percent-encoded by
      // Uri.encodeComponent, so the `code=` param appears as `code%3D`.
      expect(launchedUrl, contains('%3Fcode%3D'));
      // The raw code itself is present (unencoded).
      expect(launchedUrl, contains('HZY9ZW3J'));
    });

    testWidgets('an unauthenticated user sees the unavailable fallback',
        (tester) async {
      final unauth = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      final theme = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.lightTheme,
          home: Scaffold(
            body: ReferralShareWidget(theme: theme, repository: unauth),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Referral code unavailable'),
          findsOneWidget);
    });
  });
}