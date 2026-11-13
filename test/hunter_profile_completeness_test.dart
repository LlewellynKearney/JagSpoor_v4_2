import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/hunter_profile_completeness.dart';

/// Unit tests for [HunterProfileCompleteness] + [HunterProfileStatus].
///
/// Task 1B (2026-11-13): First Name / Surname / phone-or-email are now
/// OPTIONAL, so [HunterProfileStatus.isComplete] always returns `true` and no
/// hunter is ever bounced back to the profile screen. The per-field flags
/// remain accurate for analytics / diagnostics and are still asserted here.
/// See `docs/fix-profile-optional-fields/AUDIT.md`.
void main() {
  late FakeFirebaseFirestore db;
  late HunterProfileCompleteness checker;

  setUp(() {
    db = FakeFirebaseFirestore();
    checker = HunterProfileCompleteness.forTesting(db);
  });

  group('HunterProfileStatus.fromUserData — field flags', () {
    test('flags reflect a fully-populated profile', () {
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
    });

    test('flags reflect an email-only contact detail', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'email': 'jane@example.com',
      });
      expect(status.hasAnyContactDetail, isTrue);
    });

    test('flags reflect a profile with no contact detail', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
      });
      expect(status.hasAnyContactDetail, isFalse);
    });

    test('flags reflect a missing surname', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'phone': '+27820001111',
      });
      expect(status.hasLastName, isFalse);
    });

    test('legacy fullName with a space counts as both name parts', () {
      final status = HunterProfileStatus.fromUserData({
        'fullName': 'Jane Doe',
        'phone': '+27820001111',
      });
      expect(status.hasFirstName, isTrue);
      expect(status.hasLastName, isTrue);
    });

    test('legacy single-token fullName counts as first name only', () {
      final status = HunterProfileStatus.fromUserData({
        'fullName': 'Madonna',
        'phone': '+27820001111',
      });
      expect(status.hasFirstName, isTrue);
      expect(status.hasLastName, isFalse);
    });

    test('surname alias resolves', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'surname': 'Doe',
        'email': 'jane@example.com',
      });
      expect(status.hasLastName, isTrue);
    });

    test('cellNumber alias counts as phone', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'cellNumber': '+27820001111',
      });
      expect(status.hasPhone, isTrue);
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
    });
  });

  group('HunterProfileStatus.isComplete is neutralised (Task 1B)', () {
    test('isComplete is true for a fully-populated profile', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phone': '+27820001111',
      });
      expect(status.isComplete, isTrue);
    });

    test('isComplete is true when only names are present (no contact)', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': 'Jane',
        'lastName': 'Doe',
      });
      expect(status.isComplete, isTrue);
    });

    test('isComplete is true for a completely empty profile', () {
      const status = HunterProfileStatus();
      expect(status.isComplete, isTrue);
      expect(status.hasFirstName, isFalse);
      expect(status.hasLastName, isFalse);
      expect(status.hasAnyContactDetail, isFalse);
    });

    test('isComplete is true when every field is blank / whitespace', () {
      final status = HunterProfileStatus.fromUserData({
        'firstName': '   ',
        'lastName': '',
        'phone': '   ',
        'email': '',
      });
      expect(status.isComplete, isTrue);
    });

    test('missingSummary still reports the absent fields (diagnostics only)',
        () {
      const status = HunterProfileStatus();
      // The summary is retained for analytics / future re-enablement, but it
      // no longer drives any redirect.
      expect(status.missingSummary, 'Missing: Name, Surname, Contact details.');
    });
  });

  group('HunterProfileCompleteness.statusFor — never blocks (Task 1B)', () {
    test('a complete profile is admitted', () async {
      await db.collection('users').doc('h1').set({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phoneNumber': '+27820001111',
      });
      final status = await checker.statusFor('h1');
      expect(status.isComplete, isTrue);
    });

    test('an empty profile doc is still admitted (no bounce)', () async {
      await db.collection('users').doc('h-empty').set(<String, dynamic>{});
      final status = await checker.statusFor('h-empty');
      expect(status.isComplete, isTrue);
    });

    test('a partial profile is admitted (no bounce)', () async {
      await db.collection('users').doc('h2').set({
        'firstName': 'Jane',
        // no last name, no contact
      });
      final status = await checker.statusFor('h2');
      expect(status.isComplete, isTrue);
    });

    test('a missing user doc is admitted (no bounce)', () async {
      final status = await checker.statusFor('no-such-uid');
      expect(status.isComplete, isTrue);
    });

    test('an empty uid is admitted (no Firestore access)', () async {
      final status = await checker.statusFor('');
      expect(status.isComplete, isTrue);
    });
  });
}
