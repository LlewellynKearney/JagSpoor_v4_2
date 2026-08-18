import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/hunter_profile_completeness.dart';

/// Unit tests for [HunterProfileCompleteness] + [HunterProfileStatus].
///
/// Exercises the check against a real `FakeFirebaseFirestore` so the
/// field-alias resolution + the mandatory-profile gate contract is verified
/// end-to-end.
void main() {
  late FakeFirebaseFirestore db;
  late HunterProfileCompleteness checker;

  setUp(() {
    db = FakeFirebaseFirestore();
    checker = HunterProfileCompleteness.forTesting(db);
  });

  group('HunterProfileStatus.fromUserData', () {
    test('complete when first + last name + phone present', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phone': '+27820001111',
      });
      expect(status.hasFirstName, isTrue);
      expect(status.hasLastName, isTrue);
      expect(status.hasPhone, isTrue);
      expect(status.hasEmail, isFalse);
      expect(status.hasAnyContactDetail, isTrue);
      expect(status.isComplete, isTrue);
    });

    test('complete when first + last name + email present (no phone)', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'email': 'jane@example.com',
      });
      expect(status.isComplete, isTrue);
    });

    test('incomplete when no contact detail', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
      });
      expect(status.isComplete, isFalse);
      expect(status.missingSummary, 'Missing: Contact details.');
    });

    test('incomplete when last name missing', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'phone': '+27820001111',
      });
      expect(status.isComplete, isFalse);
      expect(status.missingSummary, 'Missing: Surname.');
    });

    test('incomplete when both name parts missing', () {
      final status = HunterProfileStatus.fromUserData({
        'phone': '+27820001111',
      });
      expect(status.isComplete, isFalse);
      expect(status.missingSummary, 'Missing: Name, Surname.');
    });

    test('legacy fullName with a space counts as both name parts', () {
      final status = HunterProfileStatus.fromUserData({
        'fullName': 'Jane Doe',
        'phone': '+27820001111',
      });
      expect(status.hasFirstName, isTrue);
      expect(status.hasLastName, isTrue);
      expect(status.isComplete, isTrue);
    });

    test('legacy single-token fullName counts as first name only', () {
      final status = HunterProfileStatus.fromUserData({
        'fullName': 'Madonna',
        'phone': '+27820001111',
      });
      expect(status.hasFirstName, isTrue);
      expect(status.hasLastName, isFalse);
      expect(status.isComplete, isFalse);
    });

    test('surname alias resolves', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'surname': 'Doe',
        'email': 'jane@example.com',
      });
      expect(status.hasLastName, isTrue);
      expect(status.isComplete, isTrue);
    });

    test('cellNumber alias counts as phone', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'cellNumber': '+27820001111',
      });
      expect(status.hasPhone, isTrue);
      expect(status.isComplete, isTrue);
    });

    test('blank / whitespace values are not present', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': '   ',
        'lastName': '',
        'phone': '   ',
      });
      expect(status.hasFirstName, isFalse);
      expect(status.hasLastName, isFalse);
      expect(status.hasPhone, isFalse);
      expect(status.isComplete, isFalse);
    });

    test('empty data -> incomplete', () {
      const status = HunterProfileStatus();
      expect(status.isComplete, isFalse);
      expect(status.missingSummary, 'Missing: Name, Surname, Contact details.');
    });
  });

  group('HunterProfileCompleteness.statusFor', () {
    test('complete profile admitted', () async {
      await db.collection('users').doc('h1').set({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phoneNumber': '+27820001111',
      });
      final status = await checker.statusFor('h1');
      expect(status.isComplete, isTrue);
    });

    test('missing user doc -> incomplete', () async {
      final status = await checker.statusFor('no-such-uid');
      expect(status.isComplete, isFalse);
    });

    test('empty uid -> incomplete (no Firestore access)', () async {
      final status = await checker.statusFor('');
      expect(status.isComplete, isFalse);
    });

    test('partial profile -> incomplete with missing summary', () async {
      await db.collection('users').doc('h2').set({
        'firstName': 'Jane',
        // no last name, no contact
      });
      final status = await checker.statusFor('h2');
      expect(status.isComplete, isFalse);
      expect(status.missingSummary, contains('Surname'));
      expect(status.missingSummary, contains('Contact details'));
    });
  });
}
