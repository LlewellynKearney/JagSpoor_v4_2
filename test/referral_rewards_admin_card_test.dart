import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/widgets/referral_rewards_admin_card.dart';
import 'package:jagspoor/features/referral/models/referral_conversion.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

/// Widget tests for the Admin Portal referral-rewards settings card.
///
/// Exercises [ReferralRewardsAdminCard] against a real `FakeFirebaseFirestore`
/// (via the injectable repository seam): load/pre-fill, inline validation
/// blocking negative / blank / non-numeric ZAR inputs, and the save ->
/// Firestore round-trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FakeFirebaseFirestore();

  late FakeFirebaseFirestore firestore;
  late ReferralRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ReferralRepository.forTesting(
      firestore: firestore,
      currentUserIdResolver: () => 'admin-1',
    );
  });

  Future<void> pumpCard(WidgetTester tester, {bool isAdmin = true}) async {
    final theme = ThemeController();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.lightTheme,
        home: Scaffold(
          body: ReferralRewardsAdminCard(
            theme: theme,
            repository: repo,
            isAdmin: isAdmin,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder hunterField() => find.byKey(const ValueKey('referralHunterRewardField'));
  Finder outfitterField() =>
      find.byKey(const ValueKey('referralOutfitterRewardField'));

  group('ReferralRewardsAdminCard', () {
    testWidgets('loads + pre-fills the live config from admin_config',
        (tester) async {
      await firestore.collection('admin_config').doc('referral_rewards').set({
        'hunterRewardZAR': 49.99,
        'outfitterRewardZAR': 499.99,
      });

      await pumpCard(tester);

      expect(find.text('Referral reward amounts (per referral, ZAR)'),
          findsOneWidget);
      expect(tester.widget<TextFormField>(hunterField()).controller?.text,
          '49.99');
      expect(tester.widget<TextFormField>(outfitterField()).controller?.text,
          '499.99');
      expect(find.text('SAVE'), findsOneWidget);
    });

    testWidgets('falls back to the documented defaults when the doc is absent',
        (tester) async {
      await pumpCard(tester);
      // _formatAmount strips a trailing ".00" (19.99 -> "19.99").
      expect(tester.widget<TextFormField>(hunterField()).controller?.text,
          '19.99');
      expect(tester.widget<TextFormField>(outfitterField()).controller?.text,
          '199.99');
    });

    testWidgets('a negative amount is blocked by the inline validator',
        (tester) async {
      await pumpCard(tester);

      await tester.enterText(hunterField(), '-10');
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(find.text('Reward amount cannot be negative.'), findsOneWidget);
      // Nothing was persisted.
      final snap = await firestore
          .collection('admin_config')
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      expect(snap.exists, isFalse);
    });

    testWidgets('a blank amount is blocked by the inline validator',
        (tester) async {
      await pumpCard(tester);

      await tester.enterText(hunterField(), '');
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(find.text('Reward amount is required.'), findsOneWidget);
      final snap = await firestore
          .collection('admin_config')
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      expect(snap.exists, isFalse);
    });

    testWidgets('a non-numeric amount is blocked by the inline validator',
        (tester) async {
      await pumpCard(tester);

      await tester.enterText(hunterField(), 'abc');
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid ZAR amount, e.g. 19.99.'), findsOneWidget);
      final snap = await firestore
          .collection('admin_config')
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      expect(snap.exists, isFalse);
    });

    testWidgets('valid amounts save to admin_config/referral_rewards',
        (tester) async {
      await pumpCard(tester);

      await tester.enterText(hunterField(), '75');
      await tester.enterText(outfitterField(), 'R 750.50');
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      final snap = await firestore
          .collection('admin_config')
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['hunterRewardZAR'], 75.0);
      expect(data['outfitterRewardZAR'], 750.5);
      // Success snackbar surfaced.
      expect(find.textContaining('Referral rewards saved'), findsOneWidget);
    });

    testWidgets('a non-admin sees the amounts but cannot save',
        (tester) async {
      await firestore.collection('admin_config').doc('referral_rewards').set({
        'hunterRewardZAR': 20.0,
        'outfitterRewardZAR': 200.0,
      });
      await pumpCard(tester, isAdmin: false);

      expect(tester.widget<TextFormField>(hunterField()).controller?.text,
          '20');
      expect(find.text('Admin-only. You are viewing the configured amounts.'),
          findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}