import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

/// Task 2B — MANUAL referral-code entry validation (P1 fallback).
///
/// Covers `ReferralRepository.checkReferralCode`, the "validate before
/// acceptance" contract the signup field uses for users who could not be
/// deep-linked (sideload / already-installed / referrer unavailable / iOS).
void main() {
  FakeFirebaseFirestore();

  late FakeFirebaseFirestore firestore;
  late ReferralRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ReferralRepository.forTesting(
      firestore: firestore,
      currentUserIdResolver: () => 'uid-new',
    );
  });

  Future<void> seedIndex(String code, {bool active = true}) async {
    await firestore.collection('referralCodes').doc(code).set({
      'code': code,
      'ownerUid': 'uid-referrer',
      'uses': 0,
      'active': active,
    });
  }

  group('ReferralRepository.checkReferralCode', () {
    test('a valid index code is accepted', () async {
      await seedIndex('JAGSPOOR7Q3X');
      final check = await repo.checkReferralCode('JAGSPOOR7Q3X');
      expect(check.valid, isTrue);
      expect(check.reason, isNull);
    });

    test('is case-insensitive + trims', () async {
      await seedIndex('JAGSPOOR7Q3X');
      final check = await repo.checkReferralCode('  jagspoor7q3x  ');
      expect(check.valid, isTrue);
    });

    test('an unknown code is rejected with a reason', () async {
      final check = await repo.checkReferralCode('NOPE1234');
      expect(check.valid, isFalse);
      expect(check.reason, isNotNull);
    });

    test('an inactive code is rejected', () async {
      await seedIndex('JAGSPOOR7Q3X', active: false);
      final check = await repo.checkReferralCode('JAGSPOOR7Q3X');
      expect(check.valid, isFalse);
      expect(check.reason, contains('no longer active'));
    });

    test('a blank code is rejected', () async {
      final check = await repo.checkReferralCode('   ');
      expect(check.valid, isFalse);
    });

    test('falls back to a legacy profile code (no index entry)', () async {
      await firestore.collection('referral_profiles').doc('uid-referrer').set({
        'userId': 'uid-referrer',
        'referralCode': 'LEGACY2345',
        'bankingDetailsProvided': false,
      });
      final check = await repo.checkReferralCode('LEGACY2345');
      expect(check.valid, isTrue);
    });
  });
}
