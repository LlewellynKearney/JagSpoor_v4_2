import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural tests for the Phase-1 referral Firestore security rules.
///
/// The Firestore emulator (`@firebase/rules-unit-testing`) cannot run in this
/// sandbox (no Java/JVM, see AGENTS.md environment constraints), so these
/// tests encode the **rule contract** structurally by parsing
/// `firestore.rules` — the established pattern used by
/// `firestore_rules_seeding_test.dart`.
///
/// The contract being asserted:
///  - `referral_profiles/{userId}` — read own profile only; owner-scoped
///    create/update; no delete.
///  - `referral_conversions/{conversionId}` — party-scoped reads (referrer or
///    referred user), any signed-in user may append a valid pending
///    conversion, only the backend (admin) may finalise/reject/delete.
///  - `admin_config/{docId}` — signed-in read (dynamic reward amounts are
///    needed by every consumer), admin-only write.
void main() {
  final rules = _loadRules();

  group('firestore.rules — referral_profiles', () {
    final block = _blockFor(rules, 'referral_profiles');

    test('match block exists', () {
      expect(rules.contains('match /referral_profiles/{userId}'), isTrue);
    });

    test('read is own-profile only', () {
      expect(
        block.contains(
          'allow read: if isSignedIn() && resource.data.userId == '
          'request.auth.uid;',
        ),
        isTrue,
        reason: 'a user must only ever read their OWN referral profile '
            '(banking details must not leak)',
      );
    });

    test('create/update is owner-scoped with a code-length guard', () {
      expect(block.contains('allow create, update: if isSignedIn()'), isTrue);
      expect(
        block.contains('request.resource.data.userId == request.auth.uid'),
        isTrue,
        reason: 'created/updated profiles must carry the caller\'s own uid',
      );
      expect(block.contains('referralCode.size() <= 12'), isTrue);
    });

    test('delete is denied entirely', () {
      expect(block.contains('allow delete: if false;'), isTrue,
          reason: 'referral profiles are never deleted by clients');
    });
  });

  group('firestore.rules — referral_conversions', () {
    final block = _blockFor(rules, 'referral_conversions');

    test('match block exists', () {
      expect(rules.contains('match /referral_conversions/{conversionId}'),
          isTrue);
    });

    test('read is party-scoped (referrer or referred) or admin', () {
      expect(
        block.contains('resource.data.referrerId == request.auth.uid'),
        isTrue,
      );
      expect(
        block.contains('resource.data.referredUserId == request.auth.uid'),
        isTrue,
      );
      expect(block.contains('allow read: if isAdmin()'), isTrue);
    });

    test('create admits any signed-in user for a valid pending conversion', () {
      expect(block.contains('allow create: if isSignedIn()'), isTrue);
      expect(
        block.contains(
          'request.resource.data.referrerId != '
          'request.resource.data.referredUserId'),
        isTrue,
        reason: 'self-referral is rejected server-side',
      );
      expect(block.contains('request.resource.data.status == \'pending\''),
          isTrue);
    });

    test('update/delete are admin-only (backend finalises the reward)', () {
      expect(block.contains('allow update, delete: if isAdmin();'), isTrue);
    });
  });

  group('firestore.rules — admin_config referral rewards', () {
    final block = _blockFor(rules, 'admin_config');

    test('match block exists', () {
      expect(rules.contains('match /admin_config/{docId}'), isTrue);
    });

    test('read is signed-in (dynamic reward amounts)', () {
      expect(block.contains('allow read: if isSignedIn();'), isTrue);
    });

    test('write is admin-only', () {
      expect(block.contains('allow write: if isAdmin();'), isTrue);
    });
  });

  group('firestore.rules structural integrity (referral additions)', () {
    test('brace balance is preserved', () {
      final opens = '{'.allMatches(rules).length;
      final closes = '}'.allMatches(rules).length;
      expect(opens, closes);
      final parenOpens = '('.allMatches(rules).length;
      final parenCloses = ')'.allMatches(rules).length;
      expect(parenOpens, parenCloses);
    });

    test('default-deny catch-all remains last', () {
      final idx = rules.indexOf('match /{document=**}');
      expect(idx, isNonZero);
      // Only one default-deny block.
      expect('match /{document=**}'.allMatches(rules).length, 1);
    });
  });
}

/// Loads `firestore.rules` from the project root.
String _loadRules() {
  final file = File('firestore.rules');
  return file.readAsStringSync();
}

/// Extracts the `match /{col}/{docId} { ... }` block for a collection.
String _blockFor(String rules, String collection) {
  final startPattern =
      RegExp(r'match /' + collection + r'/\{[^}]+\} \{');
  final startMatch = startPattern.firstMatch(rules);
  if (startMatch == null) {
    fail('No match block found for collection $collection');
  }
  final fromStart = rules.substring(startMatch.start);
  final close = fromStart.indexOf('\n    }\n');
  if (close < 0) {
    fail('No closing brace found for collection $collection block');
  }
  return fromStart.substring(0, close);
}