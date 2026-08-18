import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/hunter_contact_resolver.dart';

/// Unit tests for [HunterContactResolver] + [HunterContact].
///
/// Exercises the resolver against a real `FakeFirebaseFirestore` (no mocks
/// of the Firestore layer itself) so the field-alias resolution + the
/// best-effort fallback contract is verified end-to-end.
void main() {
  late FakeFirebaseFirestore db;
  late HunterContactResolver resolver;

  setUp(() {
    db = FakeFirebaseFirestore();
    resolver = HunterContactResolver.forTesting(db);
  });

  group('HunterContactResolver.resolve', () {
    test('resolves the hunter profile (canonical first/last name fields)',
        () async {
      await db.collection('users').doc('h1').set({
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phoneNumber': '+27820001111',
        'email': 'jane@example.com',
      });
      final contact = await resolver.resolve({'hunterId': 'h1'});
      expect(contact.firstName, 'Jane');
      expect(contact.lastName, 'Doe');
      expect(contact.fullName, 'Jane Doe');
      expect(contact.phone, '+27820001111');
      expect(contact.email, 'jane@example.com');
      expect(contact.hasFullName, isTrue);
      expect(contact.hasPhone, isTrue);
      expect(contact.hasEmail, isTrue);
      expect(contact.hasMandatoryProfile, isTrue);
    });

    test('resolves via the surname alias', () async {
      await db.collection('users').doc('h2').set({
        'firstName': 'Thabo',
        'surname': 'Mokoena',
        'phone': '+27820002222',
      });
      final contact = await resolver.resolve({'hunterId': 'h2'});
      expect(contact.firstName, 'Thabo');
      expect(contact.lastName, 'Mokoena');
      expect(contact.fullName, 'Thabo Mokoena');
      expect(contact.hasPhone, isTrue);
      expect(contact.hasEmail, isFalse);
      // Phone present -> mandatory profile satisfied even without email.
      expect(contact.hasMandatoryProfile, isTrue);
    });

    test('resolves via the cellNumber + email aliases', () async {
      await db.collection('users').doc('h3').set({
        'first_name': 'Pieter',
        'last_name': 'Botha',
        'cellNumber': '+27820003333',
        'email': 'pieter@example.com',
      });
      final contact = await resolver.resolve({'hunterId': 'h3'});
      expect(contact.firstName, 'Pieter');
      expect(contact.lastName, 'Botha');
      expect(contact.fullName, 'Pieter Botha');
      expect(contact.phone, '+27820003333');
      expect(contact.email, 'pieter@example.com');
    });

    test('resolves via the fullName alias (single legacy field)', () async {
      await db.collection('users').doc('h4').set({
        'fullName': 'Jan van Riebeeck',
        'cell': '+27820004444',
      });
      final contact = await resolver.resolve({'hunterId': 'h4'});
      // fullName does not populate first/last; composed full name is the
      // stored fullName value.
      expect(contact.firstName, '');
      expect(contact.lastName, '');
      expect(contact.fullName, 'Jan van Riebeeck');
      expect(contact.phone, '+27820004444');
      expect(contact.hasFullName, isTrue);
      expect(contact.hasPhone, isTrue);
      expect(contact.hasMandatoryProfile, isTrue);
    });

    test('falls back to the booking-doc snapshot name when profile is absent',
        () async {
      final contact = await resolver.resolve({
        'hunterId': 'missing',
        'hunterName': 'Snapshot Name',
      });
      expect(contact.firstName, '');
      expect(contact.lastName, '');
      expect(contact.fullName, 'Snapshot Name');
      expect(contact.hasPhone, isFalse);
      expect(contact.hasEmail, isFalse);
      expect(contact.hasMandatoryProfile, isFalse);
    });

    test('returns an empty contact when hunterId is missing', () async {
      final contact = await resolver.resolve(<String, dynamic>{});
      expect(contact.hunterId, '');
      expect(contact.fullName, '');
      expect(contact.hasAnyContactDetail, isFalse);
      expect(contact.hasMandatoryProfile, isFalse);
    });

    test('returns an empty contact when the user doc does not exist',
        () async {
      final contact = await resolver.resolve({'hunterId': 'no-such-doc'});
      expect(contact.fullName, '');
      expect(contact.hasAnyContactDetail, isFalse);
    });

    test('does not throw when phone + email are both absent', () async {
      await db.collection('users').doc('h5').set({
        'firstName': 'Only',
        'lastName': 'Name',
      });
      final contact = await resolver.resolve({'hunterId': 'h5'});
      expect(contact.fullName, 'Only Name');
      expect(contact.hasPhone, isFalse);
      expect(contact.hasEmail, isFalse);
      expect(contact.hasAnyContactDetail, isFalse);
      expect(contact.hasMandatoryProfile, isFalse);
    });
  });

  group('HunterContact', () {
    test('hasMandatoryProfile requires name AND a contact detail', () {
      const complete = HunterContact(
        firstName: 'Jane',
        lastName: 'Doe',
        phone: '+27820001111',
      );
      expect(complete.hasMandatoryProfile, isTrue);

      const noContact = HunterContact(
        firstName: 'Jane',
        lastName: 'Doe',
      );
      expect(noContact.hasMandatoryProfile, isFalse);

      const noName = HunterContact(phone: '+27820001111');
      expect(noName.hasMandatoryProfile, isFalse);
    });
  });
}
