import 'dart:math' as dart_math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/referral/models/referral_conversion.dart';
import 'package:jagspoor/features/referral/models/referral_profile.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

void main() {
  // Pin the fake Firestore FieldValue platform up-front (documented pattern).
  FakeFirebaseFirestore();

  group('ReferralRepository — code generation', () {
    test('generates a deterministic code from an injected Random', () {
      final rng = dart_math.Random(42);
      final code = ReferralRepository.generateReferralCode(random: rng);
      expect(code.length, 8);
      for (final c in code.split('')) {
        expect(kReferralCodeAlphabet.contains(c), isTrue,
            reason: 'generated chars must come from the safe alphabet');
      }
    });

    test('generates codes of the requested length', () {
      final code = ReferralRepository.generateReferralCode(
          length: 12, random: dart_math.Random(1));
      expect(code.length, 12);
    });

    test('generated codes differ across calls', () {
      final a = ReferralRepository.generateReferralCode(random: dart_math.Random(1));
      final b = ReferralRepository.generateReferralCode(random: dart_math.Random(2));
      expect(a, isNot(b));
    });
  });

  group('ReferralRepository — referral_profiles', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        random: dart_math.Random(7),
      );
    });

    test('getMyReferralProfile returns null when absent', () async {
      expect(await repo.getMyReferralProfile(), isNull);
    });

    test('createMyReferralProfile writes the profile + unique code', () async {
      final profile = await repo.createMyReferralProfile();
      expect(profile.userId, 'uid-1');
      expect(profile.referralCode, isNotEmpty);
      expect(profile.bankingDetailsProvided, isFalse);

      final doc = await firestore
          .collection('referral_profiles')
          .doc('uid-1')
          .get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['userId'], 'uid-1');
      expect(data['referralCode'], profile.referralCode);
      expect(data['bankingDetailsProvided'], isFalse);
    });

    test('createMyReferralProfile rejects an unauthenticated caller', () async {
      final anon = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      expect(anon.createMyReferralProfile(), throwsStateError);
    });

    test('getMyReferralProfile round-trips a created profile', () async {
      await repo.createMyReferralProfile();
      final loaded = await repo.getMyReferralProfile();
      expect(loaded, isNotNull);
      expect(loaded!.userId, 'uid-1');
      expect(loaded.referralCode, isNotEmpty);
    });

    test('getReferralProfile resolves a profile by uid', () async {
      await repo.createMyReferralProfile();
      final other = await repo.getReferralProfile('uid-1');
      expect(other, isNotNull);
      expect(other!.referralCode, isNotEmpty);
      expect(await repo.getReferralProfile('missing'), isNull);
    });

    test('updateMyBankingDetails persists + clears fields', () async {
      await repo.createMyReferralProfile();
      await repo.updateMyBankingDetails(
        bankAccountHolder: 'Jaco van Rensburg',
        bankName: 'Standard Bank',
        bankAccountNumber: '0045612345678',
        bankAccountType: 'Current',
      );
      final loaded = await repo.getMyReferralProfile();
      expect(loaded!.bankingDetailsProvided, isTrue);
      expect(loaded.bankAccountHolder, 'Jaco van Rensburg');
      expect(loaded.bankName, 'Standard Bank');
      expect(loaded.bankAccountNumber, '0045612345678');
      expect(loaded.bankAccountType, 'Current');

      // Clearing the holder flips bankingDetailsProvided back to false.
      await repo.updateMyBankingDetails(bankAccountHolder: '');
      final cleared = await repo.getMyReferralProfile();
      expect(cleared!.bankingDetailsProvided, isFalse);
      expect(cleared.bankAccountHolder, '');
    });

    test('updateMyBankingDetails rejects an unauthenticated caller', () async {
      final anon = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      expect(anon.updateMyBankingDetails(bankAccountHolder: 'X'),
          throwsStateError);
    });
  });

  group('ReferralRepository — referral_conversions', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-referrer',
      );
    });

    test('recordConversion writes a pending conversion + returns its id',
        () async {
      final id = await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new',
        referralCode: 'jagspoor-7q3x',
        subscriptionTier: ReferralSubscriptionTier.outfitter,
      );
      expect(id, isNotEmpty);
      final doc = await firestore
          .collection('referral_conversions')
          .doc(id)
          .get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['referrerId'], 'uid-referrer');
      expect(data['referredUserId'], 'uid-new');
      expect(data['referralCode'], 'JAGSPOOR-7Q3X');
      expect(data['subscriptionTier'], 'outfitter');
      expect(data['status'], 'pending');
    });

    test('recordConversion rejects self-referral', () async {
      expect(
        repo.recordConversion(
          referrerId: 'uid-referrer',
          referredUserId: 'uid-referrer',
          referralCode: 'CODE',
        ),
        throwsStateError,
      );
    });

    test('recordConversion validates required fields', () async {
      expect(
        repo.recordConversion(
          referrerId: '',
          referredUserId: 'uid-new',
          referralCode: 'CODE',
        ),
        throwsArgumentError,
      );
      expect(
        repo.recordConversion(
          referrerId: 'uid-referrer',
          referredUserId: '',
          referralCode: 'CODE',
        ),
        throwsArgumentError,
      );
      expect(
        repo.recordConversion(
          referrerId: 'uid-referrer',
          referredUserId: 'uid-new',
          referralCode: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('recordConversion rejects an unauthenticated caller', () async {
      final anon = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      expect(
        anon.recordConversion(
          referrerId: 'a',
          referredUserId: 'b',
          referralCode: 'CODE',
        ),
        throwsStateError,
      );
    });

    test('getConversionsForCurrentUser returns only the referrer\'s '
        'conversions, newest-first', () async {
      await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new-1',
        referralCode: 'CODE1',
      );
      await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new-2',
        referralCode: 'CODE2',
      );
      // Another referrer's conversion must not leak in.
      await firestore.collection('referral_conversions').add({
        'referrerId': 'uid-other',
        'referredUserId': 'uid-x',
        'referralCode': 'CODE3',
        'subscriptionTier': 'hunter',
        'status': 'pending',
      });

      final conversions = await repo.getConversionsForCurrentUser();
      expect(conversions.length, 2);
      expect(
          conversions.map((c) => c.referredUserId),
          containsAll(['uid-new-1', 'uid-new-2']));
      // Newest-first: the second-created conversion sorts first.
      final t0 = conversions[0].createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final t1 = conversions[1].createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      expect(t0.isAfter(t1) || t0 == t1, isTrue);
    });

    test('getConversionsForCurrentUser returns empty for an unauth caller',
        () async {
      final anon = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      expect(await anon.getConversionsForCurrentUser(), isEmpty);
    });

    test('getConversion fetches a single conversion by id', () async {
      final id = await repo.recordConversion(
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new',
        referralCode: 'CODE1',
      );
      final conversion = await repo.getConversion(id);
      expect(conversion, isNotNull);
      expect(conversion!.referrerId, 'uid-referrer');
      expect(conversion.referredUserId, 'uid-new');
      expect(await repo.getConversion('missing'), isNull);
    });
  });

  group('ReferralRepository — admin_config reward config', () {
    test('loadRewardConfig falls back to defaults when absent', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
      );
      final config = await repo.loadRewardConfig();
      expect(config.hunterRewardZAR,
          ReferralRewards.defaultHunterRewardZAR);
      expect(config.outfitterRewardZAR,
          ReferralRewards.defaultOutfitterRewardZAR);
    });

    test('loadRewardConfig reads the live admin document', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('admin_config').doc('referral_rewards').set({
        'hunterRewardZAR': 25.0,
        'outfitterRewardZAR': 250.0,
      });
      final repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
      );
      final config = await repo.loadRewardConfig();
      expect(config.hunterRewardZAR, 25.0);
      expect(config.outfitterRewardZAR, 250.0);
      expect(config.amountFor(ReferralSubscriptionTier.hunter), 25.0);
      expect(config.amountFor(ReferralSubscriptionTier.outfitter), 250.0);
    });
  });

  group('ReferralRepository — getOrCreateMyReferralProfile', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        random: dart_math.Random(11),
      );
    });

    test('returns the existing profile when a code is already stored',
        () async {
      await firestore.collection('referral_profiles').doc('uid-1').set({
        'userId': 'uid-1',
        'referralCode': 'EXISTING1',
        'bankingDetailsProvided': false,
      });

      final profile = await repo.getOrCreateMyReferralProfile();
      expect(profile, isNotNull);
      expect(profile!.referralCode, 'EXISTING1');
      // No new code was generated — the stored one is reused.
      final snap = await firestore
          .collection('referral_profiles')
          .doc('uid-1')
          .get();
      expect((snap.data()! as Map)['referralCode'], 'EXISTING1');
    });

    test('auto-generates + persists a code when the profile is absent',
        () async {
      final profile = await repo.getOrCreateMyReferralProfile();
      expect(profile, isNotNull);
      expect(profile!.referralCode, isNotEmpty);
      expect(profile.referralCode.length, 8);

      final snap = await firestore
          .collection('referral_profiles')
          .doc('uid-1')
          .get();
      expect(snap.exists, isTrue);
      expect((snap.data()! as Map)['referralCode'], profile.referralCode);
    });

    test('generates a fresh code when the stored profile has an empty code',
        () async {
      await firestore.collection('referral_profiles').doc('uid-1').set({
        'userId': 'uid-1',
        'referralCode': '',
        'bankingDetailsProvided': false,
      });

      final profile = await repo.getOrCreateMyReferralProfile();
      expect(profile, isNotNull);
      expect(profile!.referralCode, isNotEmpty);
    });

    test('returns null for an unauthenticated caller', () async {
      final unauth = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
      );
      expect(await unauth.getOrCreateMyReferralProfile(), isNull);
    });
  });
}