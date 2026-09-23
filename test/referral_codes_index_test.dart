import 'dart:math' as dart_math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/referral/models/referral_code.dart';
import 'package:jagspoor/features/referral/models/referral_profile.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

/// Tests for the `referralCodes/{code}` reverse index that the post-Dynamic-
/// Links App Links flow depends on (CODE -> owner uid, O(1) direct read).
void main() {
  FakeFirebaseFirestore();

  group('ReferralCode model', () {
    test('fromMap reads the canonical fields', () {
      final code = ReferralCode.fromMap(
        {
          'code': 'abc123',
          'ownerUid': 'uid-1',
          'uses': 3,
          'active': true,
        },
        id: 'abc123',
      );
      expect(code.code, 'ABC123');
      expect(code.ownerUid, 'uid-1');
      expect(code.uses, 3);
      expect(code.active, isTrue);
      expect(code.isRedeemable, isTrue);
    });

    test('fromMap tolerates owner aliases', () {
      final code = ReferralCode.fromMap(
        {'userId': 'uid-2'},
        id: 'XYZ',
      );
      expect(code.ownerUid, 'uid-2');
      expect(code.code, 'XYZ');
    });

    test('uses the doc id when no code field is present', () {
      final code = ReferralCode.fromMap({'ownerUid': 'u'}, id: 'fromid1');
      expect(code.code, 'FROMID1');
    });

    test('active defaults to true and parses a false flag', () {
      expect(ReferralCode.fromMap({'ownerUid': 'u'}, id: 'A').active, isTrue);
      expect(
        ReferralCode.fromMap({'ownerUid': 'u', 'active': false}, id: 'A').active,
        isFalse,
      );
    });

    test('isRedeemable is false when inactive or ownerless', () {
      expect(
        ReferralCode.fromMap({'ownerUid': 'u', 'active': false}, id: 'A')
            .isRedeemable,
        isFalse,
      );
      expect(ReferralCode.fromMap({}, id: 'A').isRedeemable, isFalse);
    });

    test('numeric-string uses parse', () {
      expect(
        ReferralCode.fromMap({'ownerUid': 'u', 'uses': '7'}, id: 'A').uses,
        7,
      );
    });

    test('toMap round-trips the ownership fields', () {
      const code = ReferralCode(code: 'ABC', ownerUid: 'uid-9', uses: 2);
      final map = code.toMap();
      expect(map['code'], 'ABC');
      expect(map['ownerUid'], 'uid-9');
      expect(map['uses'], 2);
      expect(map['active'], isTrue);
    });
  });

  group('ReferralRepository — referralCodes index', () {
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

    test('createMyReferralProfile also writes the reverse index', () async {
      final profile = await repo.createMyReferralProfile();
      expect(profile.referralCode, isNotEmpty);
      final index = await repo.getReferralCode(profile.referralCode);
      expect(index, isNotNull);
      expect(index!.ownerUid, 'uid-1');
      expect(index.active, isTrue);
    });

    test('getReferralCode is case-insensitive', () async {
      await firestore.collection(kReferralCodesCollection).doc('ABC123').set({
        'code': 'ABC123',
        'ownerUid': 'uid-1',
        'active': true,
      });
      final index = await repo.getReferralCode('abc123');
      expect(index?.ownerUid, 'uid-1');
    });

    test('getReferralCode returns null for an unknown code', () async {
      expect(await repo.getReferralCode('NOPE1234'), isNull);
      expect(await repo.getReferralCode(''), isNull);
    });

    test('findReferrerByCode resolves via the index faster path', () async {
      await firestore.collection(kReferralProfilesCollection).doc('uid-1').set({
        'userId': 'uid-1',
        'referralCode': 'IDXONLY1',
      });
      await firestore.collection(kReferralCodesCollection).doc('IDXONLY1').set({
        'code': 'IDXONLY1',
        'ownerUid': 'uid-1',
        'active': true,
      });
      final referrer = await repo.findReferrerByCode('idxonly1');
      expect(referrer, isNotNull);
      expect(referrer!.userId, 'uid-1');
      expect(referrer.referralCode, 'IDXONLY1');
    });

    test('findReferrerByCode still works without the reverse index (legacy)',
        () async {
      await firestore.collection(kReferralProfilesCollection).doc('uid-2').set({
        'userId': 'uid-2',
        'referralCode': 'LEGACY99',
      });
      final referrer = await repo.findReferrerByCode('LEGACY99');
      expect(referrer?.userId, 'uid-2');
    });

    test('markReferralCodeUsed increments the uses counter', () async {
      await firestore.collection(kReferralCodesCollection).doc('USE12345').set({
        'code': 'USE12345',
        'ownerUid': 'uid-1',
        'active': true,
        'uses': 1,
      });
      await repo.markReferralCodeUsed('use12345');
      final index = await repo.getReferralCode('USE12345');
      expect(index!.uses, 2);
      expect(index.lastUsedAt, isNotNull);
    });

    test('redeemReferralCode bumps the index use counter', () async {
      await firestore.collection(kReferralProfilesCollection).doc('referrer').set({
        'userId': 'referrer',
        'referralCode': 'REDEEM01',
      });
      await firestore.collection(kReferralCodesCollection).doc('REDEEM01').set({
        'code': 'REDEEM01',
        'ownerUid': 'referrer',
        'active': true,
        'uses': 0,
      });
      final result = await repo.redeemReferralCode(
        referredUserId: 'newbie',
        referralCode: 'REDEEM01',
      );
      expect(result.isRecorded, isTrue);
      final index = await repo.getReferralCode('REDEEM01');
      expect(index!.uses, 1);
    });
  });
}
