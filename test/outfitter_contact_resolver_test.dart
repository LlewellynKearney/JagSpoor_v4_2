import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/outfitter_contact_resolver.dart';

/// Unit tests for [OutfitterContactResolver] + [OutfitterContact].
///
/// Exercises the resolver against a real `FakeFirebaseFirestore` (no mocks of
/// the Firestore layer itself) so the field-alias resolution + the
/// best-effort fallback contract is verified end-to-end.
void main() {
  late FakeFirebaseFirestore db;
  late OutfitterContactResolver resolver;

  setUp(() {
    db = FakeFirebaseFirestore();
    resolver = OutfitterContactResolver.forTesting(db);
  });

  group('OutfitterContactResolver.resolve', () {
    test('resolves the outfitter profile (canonical field names)', () async {
      await db.collection('outfitters').doc('o1').set({
        'displayName': 'Bushveld Outfitters',
        'email': 'book@bushveld.example',
        'phoneNumber': '+27821234567',
      });
      final contact = await resolver.resolve({'outfitterId': 'o1'});
      expect(contact.outfitterName, 'Bushveld Outfitters');
      expect(contact.outfitterEmail, 'book@bushveld.example');
      expect(contact.outfitterPhone, '+27821234567');
      expect(contact.hasAnyContact, isTrue);
      expect(contact.hasAnyManager, isFalse);
      // No manager -> primary contact is the outfitter.
      expect(contact.primaryContactName, 'Bushveld Outfitters');
      expect(contact.primaryContactRole, 'Outfitter');
      expect(contact.primaryPhone, '+27821234567');
      expect(contact.primaryEmail, 'book@bushveld.example');
    });

    test('resolves the outfitter profile (alias field names)', () async {
      await db.collection('outfitters').doc('o2').set({
        'businessName': 'Savanna Safaris',
        'phone': '+27820000000',
        // email absent
      });
      final contact = await resolver.resolve({'outfitterId': 'o2'});
      expect(contact.outfitterName, 'Savanna Safaris');
      expect(contact.outfitterPhone, '+27820000000');
      expect(contact.hasOutfitterEmail, isFalse);
      expect(contact.primaryEmail, '');
    });

    test('resolves a farm manager as the primary contact when assigned',
        () async {
      await db.collection('outfitters').doc('o3').set({
        'displayName': 'Outfitter A',
        'email': 'outfitter@example',
        'phoneNumber': '+27821111111',
      });
      await db.collection('farm_managers').add({
        'farmId': 'f3',
        'outfitterId': 'o3',
        'managerName': 'Jane Manager',
        'managerEmail': 'jane@example',
        'managerCell': '+27822222222',
        'cellNr': '+27822222222',
        'status': 'Active',
      });
      final contact = await resolver.resolve({
        'outfitterId': 'o3',
        'farmId': 'f3',
      });
      expect(contact.hasAnyManager, isTrue);
      // Manager takes precedence as the primary contact.
      expect(contact.primaryContactName, 'Jane Manager');
      expect(contact.primaryContactRole, 'Farm Manager');
      expect(contact.primaryPhone, '+27822222222');
      expect(contact.primaryEmail, 'jane@example');
      // Outfitter details still resolved.
      expect(contact.outfitterName, 'Outfitter A');
    });

    test('resolves a farm manager via the cellNr alias', () async {
      await db.collection('farm_managers').add({
        'farmId': 'f4',
        'outfitterId': 'o4',
        'managerName': 'Alias Manager',
        'managerEmail': 'alias@example',
        // managerCell absent; cellNr present
        'cellNr': '+27823333333',
      });
      final contact = await resolver.resolve({
        'outfitterId': 'o4',
        'farmId': 'f4',
      });
      expect(contact.managerPhone, '+27823333333');
      expect(contact.primaryPhone, '+27823333333');
    });

    test('returns an empty contact when the outfitter doc is missing',
        () async {
      final contact = await resolver.resolve({'outfitterId': 'nope'});
      expect(contact.hasAnyContact, isFalse);
      expect(contact.outfitterName, '');
      expect(contact.primaryContactName, '');
    });

    test('returns an empty contact when outfitterId is absent', () async {
      final contact = await resolver.resolve(<String, dynamic>{});
      expect(contact.hasAnyContact, isFalse);
    });

    test('does not throw when a farmId is present but no manager is assigned',
        () async {
      await db.collection('outfitters').doc('o5').set({
        'displayName': 'Outfitter E',
        'email': 'e@example',
      });
      final contact = await resolver.resolve({
        'outfitterId': 'o5',
        'farmId': 'f-no-manager',
      });
      expect(contact.hasAnyManager, isFalse);
      expect(contact.outfitterName, 'Outfitter E');
      expect(contact.primaryContactRole, 'Outfitter');
    });

    test('falls back gracefully on a Firestore fetch error', () async {
      // The production singleton uses the lazy _firestore getter which
      // resolves to FirebaseFirestore.instance -- which throws [core/no-app]
      // in a test with no Firebase app. The resolver's resolve() wraps both
      // the outfitter + manager fetches in try/catch, so it must return an
      // empty contact instead of propagating the error.
      final contact =
          await OutfitterContactResolver.instance.resolve({'outfitterId': 'o'});
      expect(contact.hasAnyContact, isFalse);
    });
  });

  group('OutfitterContact getters', () {
    test('hasAnyContact is false for a fully-empty contact', () {
      const contact = OutfitterContact();
      expect(contact.hasAnyContact, isFalse);
      expect(contact.hasAnyManager, isFalse);
      expect(contact.primaryContactName, '');
      expect(contact.primaryContactRole, 'Outfitter'); // default when no name
    });

    test('primary contact falls back to outfitter when manager has no name',
        () {
      const contact = OutfitterContact(
        outfitterName: 'Outfitter X',
        outfitterPhone: '+27820000001',
        // manager has a phone but no name -> not the primary
        managerPhone: '+27820000002',
      );
      // managerName empty -> primary is outfitter
      expect(contact.primaryContactName, 'Outfitter X');
      expect(contact.primaryContactRole, 'Outfitter');
      // but manager phone is present so hasAnyManager is true
      expect(contact.hasAnyManager, isTrue);
    });
  });
}
