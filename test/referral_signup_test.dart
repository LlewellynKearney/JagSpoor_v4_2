import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/auth/auth_screen.dart';
import 'package:jagspoor/features/referral/models/referral_conversion.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

/// Phase-4 referral signup tests.
///
/// Covers the two new repository surfaces — [ReferralRepository
/// .findReferrerByCode] (code → referrer UID lookup) and
/// [ReferralRepository.redeemReferralCode] (the signup hook that validates a
/// code, rejects self-referrals, and writes a `pending` conversion with the
/// correct tier reward amount) — plus the auth-screen registration field
/// wiring. All repository tests run against a real `FakeFirebaseFirestore`
/// via the injectable `forTesting` seam; the widget test asserts the
/// registration-only field renders without touching Firebase.
void main() {
  // Pin the fake Firestore FieldValue platform up-front (documented pattern).
  FakeFirebaseFirestore();

  group('ReferralRepository.findReferrerByCode', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-new',
      );
    });

    test('resolves the referrer profile for a stored code (case-insensitive)',
        () async {
      await firestore.collection('referral_profiles').doc('uid-referrer').set({
        'userId': 'uid-referrer',
        'referralCode': 'JAGSPOOR7Q3X',
        'bankingDetailsProvided': false,
      });

      final referrer = await repo.findReferrerByCode('jagspoor7q3x');
      expect(referrer, isNotNull);
      expect(referrer!.userId, 'uid-referrer');
      expect(referrer.referralCode, 'JAGSPOOR7Q3X');
    });

    test('returns null for a code with no matching profile', () async {
      await firestore.collection('referral_profiles').doc('uid-referrer').set({
        'userId': 'uid-referrer',
        'referralCode': 'JAGSPOOR7Q3X',
        'bankingDetailsProvided': false,
      });

      expect(await repo.findReferrerByCode('NOPE1234'), isNull);
    });

    test('returns null for a blank code (never throws)', () async {
      expect(await repo.findReferrerByCode(''), isNull);
      expect(await repo.findReferrerByCode('   '), isNull);
      expect(await repo.findReferrerByCode(''), isNull);
    });
  });

  group('ReferralRepository.redeemReferralCode', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-new',
      );
      // Seed a referrer profile whose code the new signup will redeem.
      firestore.collection('referral_profiles').doc('uid-referrer').set({
        'userId': 'uid-referrer',
        'referralCode': 'JAGSPOOR7Q3X',
        'bankingDetailsProvided': false,
      });
    });

    test('records a pending conversion with the hunter-tier reward', () async {
      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: 'jagspoor7q3x',
      );

      expect(result.isRecorded, isTrue);
      expect(result.conversionId, isNotEmpty);

      final doc = await firestore
          .collection('referral_conversions')
          .doc(result.conversionId!)
          .get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['referrerId'], 'uid-referrer');
      expect(data['referredUserId'], 'uid-new');
      expect(data['referralCode'], 'JAGSPOOR7Q3X');
      expect(data['subscriptionTier'], 'hunter');
      expect(data['status'], 'pending');
      // Hunter tier → the documented default hunter reward.
      expect(data['rewardAmountZAR'],
          ReferralRewards.defaultHunterRewardZAR);
    });

    test('records a pending conversion with the outfitter-tier reward',
        () async {
      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: 'JAGSPOOR7Q3X',
        subscriptionTier: ReferralSubscriptionTier.outfitter,
      );

      expect(result.isRecorded, isTrue);
      final doc = await firestore
          .collection('referral_conversions')
          .doc(result.conversionId!)
          .get();
      expect(doc.data()!['subscriptionTier'], 'outfitter');
      expect(doc.data()!['rewardAmountZAR'],
          ReferralRewards.defaultOutfitterRewardZAR);
    });

    test('uses the live admin reward config when present', () async {
      await firestore.collection('admin_config').doc('referral_rewards').set({
        'hunterRewardZAR': 25.0,
        'outfitterRewardZAR': 250.0,
      });

      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: 'JAGSPOOR7Q3X',
      );
      expect(result.isRecorded, isTrue);
      final doc = await firestore
          .collection('referral_conversions')
          .doc(result.conversionId!)
          .get();
      expect(doc.data()!['rewardAmountZAR'], 25.0);
    });

    test('skips a blank code without writing a conversion', () async {
      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: '   ',
      );

      expect(result.isRecorded, isFalse);
      expect(result.conversionId, isNull);
      final snap = await firestore
          .collection('referral_conversions')
          .get();
      expect(snap.docs, isEmpty);
    });

    test('skips an invalid / non-existent code without blocking', () async {
      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: 'BOGUS9999',
      );

      expect(result.isRecorded, isFalse);
      expect(result.message, isNotNull);
      final snap = await firestore
          .collection('referral_conversions')
          .get();
      expect(snap.docs, isEmpty);
    });

    test('skips a self-referral without writing a conversion', () async {
      // The new account IS the referrer (e.g. a stale session reused the
      // code) — must be rejected, never recorded.
      final result = await repo.redeemReferralCode(
        referredUserId: 'uid-referrer',
        referralCode: 'JAGSPOOR7Q3X',
      );

      expect(result.isRecorded, isFalse);
      expect(result.message, contains('themself'));
      final snap = await firestore
          .collection('referral_conversions')
          .get();
      expect(snap.docs, isEmpty);
    });

    test('never throws on a Firestore failure — returns skipped', () async {
      // A repository bound to a uid resolver that throws on Firestore access
      // exercises the catch-all path (registration proceeds normally).
      final broken = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-new',
      );
      // Force the Firestore read to fail by pointing at a non-existent app.
      broken.firestoreForTesting = null;

      // The production singleton would throw [core/no-app]; redeemReferralCode
      // must swallow it and report a skip instead.
      final result = await broken.redeemReferralCode(
        referredUserId: 'uid-new',
        referralCode: 'JAGSPOOR7Q3X',
      );
      expect(result.isRecorded, isFalse);
    });
  });

  group('ReferralRepository.recordConversion reward amount', () {
    test('writes rewardAmountZAR only when positive', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-referrer',
      );

      final id = await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new',
        referralCode: 'CODE1',
        rewardAmountZAR: 19.99,
      );
      final doc = await firestore
          .collection('referral_conversions')
          .doc(id)
          .get();
      expect(doc.data()!['rewardAmountZAR'], 19.99);

      // Zero / negative amounts are omitted (the model omits <= 0).
      final id2 = await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new-2',
        referralCode: 'CODE2',
        rewardAmountZAR: 0.0,
      );
      final doc2 = await firestore
          .collection('referral_conversions')
          .doc(id2)
          .get();
      expect(doc2.data()!.containsKey('rewardAmountZAR'), isFalse);
    });
  });

  group('AuthScreen registration referral field', () {
    Widget buildScreen() {
      return MaterialApp(
        home: AuthScreen(themedata: ThemeController()),
      );
    }

    testWidgets('registration mode shows the optional referral code field',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Default mode is login — the referral field must be absent.
      expect(
        find.byKey(const ValueKey('registrationReferralCodeField')),
        findsNothing,
      );

      // Switch to registration. The switch button can sit below the fold on
      // the 800x600 test surface — bring it into view first.
      await tester.ensureVisible(find.text('SWITCH TO REGISTRATION'));
      await tester.pump();
      await tester.tap(find.text('SWITCH TO REGISTRATION'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('registrationReferralCodeField')),
        findsOneWidget,
      );
      expect(find.text('Referral Code (optional)'), findsOneWidget);
    });

    testWidgets('login mode never shows the referral code field',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('registrationReferralCodeField')),
        findsNothing,
      );
      expect(find.text('Referral Code (optional)'), findsNothing);
    });
  });
}
