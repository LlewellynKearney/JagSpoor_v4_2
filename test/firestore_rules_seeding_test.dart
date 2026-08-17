import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural tests for the Firestore security rules that gate the startup
/// seeding collections (v4.5 to-do Item #5).
///
/// The Firestore emulator (`@firebase/rules-unit-testing`) cannot run in this
/// sandbox (no Java/JVM, see AGENTS.md environment constraints), so these
/// tests encode the **rule contract** structurally by parsing
/// `firestore.rules` and asserting the allow statements that gate the
/// `factory_ammunition` / `bullets` / `propellants` collections — the three
/// reference catalog collections `BallisticsSeeder.seedAll()` writes to at
/// first launch (from `main.dart`, for every signed-in user). This mirrors
/// the pattern used by `package_quantity_test.dart` /
/// `custom_package_pricing_test.dart`, which encode the transactional
/// contract the rules enforce.
///
/// The contract being asserted:
/// - Read: any signed-in user (ballistic calc pickers, marketplace).
/// - Create / update: any signed-in user — this is what eliminates the
///   `PERMISSION_DENIED` during startup seeding for non-admin users (the
///   previous `write: isAdmin()` gate blocked the one-time reference-data
///   seed for every hunter / outfitter on first launch).
/// - Delete: admin only — a non-admin must never wipe the shared catalog.
void main() {
  final rules = _loadRules();

  group('firestore.rules structural integrity', () {
    test('helpers intact', () {
      for (final h in [
        'isSignedIn',
        'isAdmin',
        'isOwnerOf',
        'ownerOrAdmin',
      ]) {
        expect(rules.contains('function $h('), isTrue,
            reason: 'helper $h missing — would break every allow clause');
      }
    });

    test('default-deny present', () {
      expect(rules.contains('allow read, write: if false;'), isTrue,
          reason: 'the catch-all default-deny must remain');
    });

    test('brace-balanced', () {
      final opens = '('.allMatches(rules).length;
      final closes = ')'.allMatches(rules).length;
      expect(opens, closes,
          reason: 'parentheses must be balanced in firestore.rules');
      final openBraces = '{'.allMatches(rules).length;
      final closeBraces = '}'.allMatches(rules).length;
      expect(openBraces, closeBraces,
          reason: 'braces must be balanced in firestore.rules');
    });
  });

  group('startup seeding collections — permission contract', () {
    for (final col in ['factory_ammunition', 'bullets', 'propellants']) {
      test('$col: read = isSignedIn()', () {
        final block = _blockFor(rules, col);
        expect(block, contains('allow read: if isSignedIn()'));
      });

      test('$col: create, update = isSignedIn() (enables startup seeding)', () {
        final block = _blockFor(rules, col);
        expect(block, contains('allow create, update: if isSignedIn()'));
        // The old bare `allow write: if isAdmin()` gate (which blocked the
        // one-time seed for non-admins) must NOT remain.
        expect(block, isNot(contains('allow write: if isAdmin()')));
      });

      test('$col: delete = isAdmin() (catalog cannot be wiped)', () {
        final block = _blockFor(rules, col);
        expect(block, contains('allow delete: if isAdmin()'));
      });
    }
  });

  group('other startup-read collections — read access', () {
    // `scanned_pricelists` is read by the custom-package farm-selection
    // filter (Phase 26); must remain isSignedIn-read (not owner-only).
    test('scanned_pricelists: read = isSignedIn()', () {
      final block = _blockFor(rules, 'scanned_pricelists');
      expect(block, contains('allow read: if isSignedIn()'));
    });

    // `animals` is the SA Game Guide catalog — public read preserved.
    // Seeded at startup by `seedAnimalsFromCSV()` (forced via the
    // `game_guide_seed_version` version tag) for every signed-in user, so
    // create/update is open to authenticated users (enables the startup
    // seed) and delete stays admin-only. (v4.5 to-do Item #6.)
    test('animals: public read + authenticated create/update (startup seed) '
        '+ admin delete', () {
      final block = _blockFor(rules, 'animals');
      expect(block, contains('allow read: if true;'));
      expect(block, contains('allow create, update: if isSignedIn()'));
      expect(block, contains('allow delete: if isAdmin()'));
      // The old bare `allow write: if isAdmin()` gate (which blocked the
      // startup game-guide seed for non-admins) must NOT remain.
      expect(block, isNot(contains('allow write: if isAdmin()')));
    });
  });

  // ── Bookings enterprise access contract ──────────────────────────────────
  //
  // The outfitter booking dashboard queries `.where('outfitterId',
  // isEqualTo: currentUserId)`; the hunter marketplace queries
  // `.where('hunterId', isEqualTo: uid)`. Firestore's query-based security
  // only validates a list query whose filter constrains a field the read
  // rule checks against `request.auth.uid`. So the bookings `read` rule must
  // explicitly grant read when `resource.data.outfitterId ==
  // request.auth.uid` (the outfitter enterprise path) and when
  // `resource.data.hunterId == request.auth.uid` (the hunter path). These
  // tests encode that contract structurally (the emulator can't run here).
  group('firestore.rules bookings enterprise access', () {
    test('bookings match block present', () {
      expect(rules.contains('match /bookings/{bookingId}'), isTrue);
    });

    test('outfitter read is explicit (outfitterId == request.auth.uid)', () {
      // The outfitter enterprise read path: an authenticated user whose uid
      // matches `outfitterId` on the booking may read/query bookings where
      // they are the outfitter. The dedicated helper makes this contract
      // explicit and queryable for the outfitter's list query.
      expect(rules.contains('function isBookingOutfitter()'), isTrue);
      expect(
        rules.contains(
          'resource.data.outfitterId == request.auth.uid',
        ),
        isTrue,
        reason: 'The outfitter read must check outfitterId == '
            'request.auth.uid so the outfitter list query is queryable.',
      );
    });

    test('hunter read is explicit (hunterId == request.auth.uid)', () {
      expect(rules.contains('function isBookingHunter()'), isTrue);
      expect(
        rules.contains('resource.data.hunterId == request.auth.uid'),
        isTrue,
      );
    });

    test('bookings read grants hunter OR outfitter OR manager OR admin', () {
      final block = _blockFor(rules, 'bookings');
      expect(
        block.contains(
          'allow read: if isAdmin() || isBookingParty() || '
          'isFarmManagerForBooking()',
        ),
        isTrue,
        reason: 'The outfitter (isBookingOutfitter via isBookingParty), the '
            'hunter (isBookingHunter via isBookingParty), a farm manager on '
            'the booking\'s farm (isFarmManagerForBooking), and an admin '
            'may all read bookings.',
      );
    });

    test('farm-manager enterprise read path is present', () {
      // A farm manager assigned to the booking's farm may read it (single-doc
      // reads, e.g. the calendar package-fallback fetch). The check looks up
      // farm_managers/{uid} and matches farmId.
      expect(rules.contains('function isFarmManagerForBooking()'), isTrue);
      expect(
        rules.contains(r'farm_managers/$(request.auth.uid)'),
        isTrue,
      );
    });

    test('bookings create requires hunterId == caller (no spoofing)', () {
      final block = _blockFor(rules, 'bookings');
      expect(
        block.contains(
          'allow create: if isSignedIn()\n'
          '        && request.resource.data.hunterId == request.auth.uid',
        ),
        isTrue,
        reason: 'A signed-in user may create a booking only under their own '
            'hunterId (no spoofed bookings under another hunter).',
      );
    });

    test('status flip is outfitter-only (statusUpdateAllowed)', () {
      final block = _blockFor(rules, 'bookings');
      expect(block.contains('function statusUpdateAllowed()'), isTrue);
      expect(
        block.contains('resource.data.outfitterId == request.auth.uid'),
        isTrue,
        reason: 'Only the outfitter may flip the booking status field.',
      );
      // Non-outfitter update path freezes the status field.
      expect(
        block.contains(
          'request.resource.data.status == resource.data.status',
        ),
        isTrue,
        reason: 'A non-outfitter booking party may update only non-status '
            'fields (the status field is frozen for them).',
      );
    });

    test('bookings delete is admin-only', () {
      final block = _blockFor(rules, 'bookings');
      expect(block.contains('allow delete: if isAdmin();'), isTrue);
    });
  });
}

/// Loads `firestore.rules` from the project root.
String _loadRules() {
  // Run from the project root (flutter test sets the CWD to the package root).
  final file = File('firestore.rules');
  return file.readAsStringSync();
}

/// Extracts the `match /{col}/{docId} { ... }` block for a collection.
///
/// Captures from the `match /{col}/{docId} {` line up to (but not including)
/// the next `    }` that sits at the 4-space indentation level (the closing
/// brace of the match block). This tolerates nested content / comments
/// inside the block.
String _blockFor(String rules, String collection) {
  final startPattern =
      RegExp(r'match /' + collection + r'/\{[^}]+\} \{');
  final startMatch = startPattern.firstMatch(rules);
  if (startMatch == null) {
    fail('No match block found for collection $collection');
  }
  // Take from the match-block opening line through the closing brace at the
  // 4-space indent that ends a top-level collection match block.
  final fromStart = rules.substring(startMatch.start);
  final close = fromStart.indexOf('\n    }\n');
  if (close < 0) {
    fail('No closing brace found for collection $collection block');
  }
  return fromStart.substring(0, close);
}
