import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/outfitter_enterprise_manager.dart';

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

  // ── users/{userId} profile write contract (hotfix) ───────────────────────
  //
  // The hunter profile screen writes medical info (bloodType / allergies /
  // medicalAid / emergencyContact), legal compliance (idNumber /
  // hunterStatus / provincialPermits), battery settings, and every other
  // profile field to `users/{uid}` via `set(merge: true)`. The owner must
  // have full permission to write and update their own profile fields
  // without a permission-denied error. The single restricted field is
  // `deviceFingerprint` (device-level trial-abuse prevention), which stays
  // immutable once set.
  group('users/{userId} profile write contract (hotfix)', () {
    test('users read = isSignedIn()', () {
      final block = _blockFor(rules, 'users');
      expect(block, contains('allow read: if isSignedIn()'));
    });

    test('users create = owner-scoped signed-in', () {
      final block = _blockFor(rules, 'users');
      expect(
        block,
        contains('allow create: if isSignedIn() && request.auth.uid == userId;'),
      );
    });

    test('users update = owner-scoped signed-in (full profile fields)', () {
      final block = _blockFor(rules, 'users');
      expect(block, contains('allow update: if isSignedIn() && request.auth.uid == userId'));
    });

    test('users update restricts ONLY deviceFingerprint (immutability kept)', () {
      final block = _blockFor(rules, 'users');
      // The trial-abuse immutability clause must remain intact.
      expect(block, contains("resource.data.has('deviceFingerprint')"));
      expect(
        block,
        contains('resource.data.deviceFingerprint == '
            'request.resource.data.deviceFingerprint'),
      );
      // No OTHER field may be restricted in the update grant — the owner
      // must be able to update every profile field (medical info, legal
      // compliance, battery settings, …) without a permission-denied.
      final restrictions = RegExp(r"resource\.data\.has\('([^']+)'\)")
          .allMatches(block)
          .map((m) => m.group(1))
          .toList();
      expect(restrictions, ['deviceFingerprint'],
          reason: 'only deviceFingerprint may be frozen on the users doc');
    });

    test('users delete = owner-scoped signed-in (GDPR account deletion)', () {
      final block = _blockFor(rules, 'users');
      // AccountDeletionService batch-deletes users/{uid}; without an owner
      // delete grant the whole deletion batch fails with permission-denied.
      expect(
        block,
        contains('allow delete: if isSignedIn() && request.auth.uid == userId;'),
      );
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

  // ── Trophy collection separation contract ────────────────────────────────
  //
  // The outfitter's saleable trophy stock inventory must live in a dedicated
  // `trophy_stock` collection, distinct from the hunter's personal Digital
  // Trophy Room (`trophies`, scoped by `ownerId`). These tests encode the
  // separation contract structurally (the Firestore emulator can't run in
  // this sandbox — see AGENTS.md environment constraints).
  group('firestore.rules trophy stock separation', () {
    test('dedicated trophy_stock match block exists', () {
      expect(rules.contains('match /trophy_stock/{trophyId}'), isTrue,
          reason: 'The outfitter trophy stock inventory must have its own '
              'dedicated collection, separate from the hunter trophy room.');
    });

    test('trophy_stock: read = isSignedIn() (marketplace browse)', () {
      final block = _blockFor(rules, 'trophy_stock');
      expect(block, contains('allow read: if isSignedIn()'));
    });

    test('trophy_stock: writes are outfitter-owner-scoped', () {
      final block = _blockFor(rules, 'trophy_stock');
      expect(block, contains("ownerOrAdmin('outfitterId')"),
          reason: 'Only the owning outfitter (or an admin) may create / '
              'delete trophy stock entries.');
    });

    test('trophy_stock: hunter stock-decrement allowed on update (booking '
        'flow)', () {
      // The hunter booking flow (`PackageBookingManager.bookTrophyStock`)
      // decrements `availableCount` in the same atomic transaction. The
      // update rule must therefore ALSO permit a signed-in hunter's tightly
      // scoped decrement (mirrors the `packages` isInventoryDecrement
      // allowance): identity + price fields frozen, count strictly lower.
      final block = _blockFor(rules, 'trophy_stock');
      expect(block, contains('function isStockDecrement()'),
          reason: 'The hunter booking txn needs a decrement-only update '
              'allowance on trophy_stock.');
      expect(
          block,
          contains(
              'allow update: if isOwner() || isStockDecrement() || isAdmin();'),
          reason: 'trophy_stock update must permit owner OR the hunter '
              'decrement (booking) OR admin.');
      expect(
          block,
          contains('request.resource.data.availableCount\n'
              '              < resource.data.availableCount'),
          reason: 'The decrement allowance must strictly REQUIRE the '
              'availableCount to decrease (a hunter can never raise stock).');
    });

    test('trophies (hunter room) match block still exists', () {
      expect(rules.contains('match /trophies/{trophyId}'), isTrue,
          reason: 'The hunter personal Digital Trophy Room collection must '
              'remain on `trophies` (scoped by ownerId).');
    });

    test('trophies read remains isSignedIn() (sharing)', () {
      final block = _blockFor(rules, 'trophies');
      expect(block, contains('allow read: if isSignedIn()'));
    });
  });

  // ── Trophy stock collection-name constant contract ───────────────────────
  //
  // Guards against a regression where an outfitter-side service / screen
  // accidentally reads or writes the hunter `trophies` collection instead of
  // the dedicated `trophy_stock` collection.
  group('outfitter trophy stock collection-name contract', () {
    test('OutfitterEnterpriseManager.trophyStockCollection == trophy_stock',
        () {
      expect(OutfitterEnterpriseManager.trophyStockCollection, 'trophy_stock');
    });

    test('no outfitter-side code reads/writes the hunter trophies collection',
        () {
      // The outfitter enterprise manager must NOT touch the hunter `trophies`
      // collection — all four trophy-stock methods route through the dedicated
      // collection constant.
      final src = File(
        'lib/features/hunter_mode/services/outfitter_enterprise_manager.dart',
      ).readAsStringSync();
      // No raw `collection('trophies')` should remain in the manager.
      expect(src.contains("collection('trophies')"), isFalse,
          reason: 'OutfitterEnterpriseManager must use trophyStockCollection, '
              'not the hunter trophies collection.');
      // The dedicated collection constant is referenced.
      expect(src.contains('trophyStockCollection'), isTrue);
    });

    test('trophy_inventory_report_exporter reads trophy_stock', () {
      final src = File(
        'lib/features/hunter_mode/services/trophy_inventory_report_exporter.dart',
      ).readAsStringSync();
      expect(src.contains('trophyStockCollection'), isTrue);
      expect(src.contains("collection('trophies')"), isFalse);
    });

    test('outfitter_analytics_service reads trophy_stock', () {
      final src = File(
        'lib/features/hunter_mode/services/outfitter_analytics_service.dart',
      ).readAsStringSync();
      expect(src.contains('trophyStockCollection'), isTrue);
      expect(src.contains("collection('trophies')"), isFalse);
    });

    test('hunter_trophy_browser_screen reads trophy_stock (outfitter stock)',
        () {
      // The hunter-facing Trophy Registry browses the OUTFITTER stock
      // collection, not the hunter personal trophy room.
      final src = File(
        'lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart',
      ).readAsStringSync();
      expect(src.contains('trophyStockCollection'), isTrue);
      expect(src.contains("collection('trophies')"), isFalse);
    });

    test('outfitter_trophy_stock_screen streams trophy_stock', () {
      final src = File(
        'lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart',
      ).readAsStringSync();
      expect(src.contains('trophyStockCollection'), isTrue);
      expect(src.contains("collection('trophies')"), isFalse);
    });

    test('admin_analytics_service counts trophy_stock', () {
      final src = File(
        'lib/features/admin/services/admin_analytics_service.dart',
      ).readAsStringSync();
      expect(src.contains('trophyStockCollection'), isTrue);
      expect(src.contains("collection('trophies')"), isFalse);
    });

    test('hunter trophy_room_screen still uses trophies (personal room)', () {
      // The hunter's personal Digital Trophy Room MUST remain on `trophies`
      // (scoped by ownerId). This is the inverse guard: the hunter room was
      // NOT migrated.
      final src = File(
        'lib/features/hunter_mode/trophy_room_screen.dart',
      ).readAsStringSync();
      expect(src.contains("collection('trophies')"), isTrue,
          reason: 'The hunter personal Digital Trophy Room must stay on the '
              'trophies collection (scoped by ownerId).');
      expect(src.contains('trophyStockCollection'), isFalse,
          reason: 'The hunter personal trophy room must not reference the '
              'outfitter trophy_stock collection.');
    });
  });

  group('venison_permits hunter visibility contract', () {
    test('venison_permits match block exists', () {
      final rules = _loadRules();
      final block = _blockFor(rules, 'venison_permits');
      expect(block, isNotEmpty);
    });

    test('read grants the hunter via hunterId', () {
      final block = _blockFor(_loadRules(), 'venison_permits');
      expect(
        block.contains('resource.data.hunterId == request.auth.uid'),
        isTrue,
      );
    });

    test('read grants the hunter via the userId alias (dual-stamp)', () {
      final block = _blockFor(_loadRules(), 'venison_permits');
      expect(
        block.contains('resource.data.userId == request.auth.uid'),
        isTrue,
        reason: 'The read rule must accept the userId alias so permits '
            'stamped with only the legacy alias remain readable by the hunter.',
      );
    });

    test('read grants the issuing outfitter + admin', () {
      final block = _blockFor(_loadRules(), 'venison_permits');
      expect(
        block.contains('resource.data.outfitterId == request.auth.uid'),
        isTrue,
      );
      expect(block.contains('isAdmin()'), isTrue);
    });

    test('read requires authentication (not public)', () {
      final block = _blockFor(_loadRules(), 'venison_permits');
      expect(block.contains('allow read: if isSignedIn()'), isTrue);
    });

    test('delete stays least-privilege (outfitter owner or admin)', () {
      final block = _blockFor(_loadRules(), 'venison_permits');
      expect(
        block.contains("allow delete: if isOwnerOf('outfitterId') || isAdmin()"),
        isTrue,
      );
    });
  });

  group('role-partitioned venison permits collections', () {
    for (final collection in const [
      'outfitter_venison_permits',
      'hunter_venison_permits',
    ]) {
      group(collection, () {
        test('match block exists', () {
          final block = _blockFor(_loadRules(), collection);
          expect(block, isNotEmpty);
        });

        test('read is party-scoped (outfitter + hunter + userId alias + admin)',
            () {
          final block = _blockFor(_loadRules(), collection);
          expect(
            block.contains('resource.data.outfitterId == request.auth.uid'),
            isTrue,
          );
          expect(
            block.contains('resource.data.hunterId == request.auth.uid'),
            isTrue,
          );
          expect(
            block.contains('resource.data.userId == request.auth.uid'),
            isTrue,
          );
          expect(block.contains('isAdmin()'), isTrue);
        });

        test('read requires authentication (not public)', () {
          final block = _blockFor(_loadRules(), collection);
          expect(block.contains('allow read: if isSignedIn()'), isTrue);
        });

        test('create + update are allowed for signed-in parties', () {
          final block = _blockFor(_loadRules(), collection);
          expect(
            block.contains('allow create, update: if isSignedIn()'),
            isTrue,
          );
        });

        test('delete stays least-privilege (outfitter owner or admin)', () {
          final block = _blockFor(_loadRules(), collection);
          expect(
            block.contains(
              "allow delete: if isOwnerOf('outfitterId') || isAdmin()",
            ),
            isTrue,
          );
        });
      });
    }

    test('the outfitter partition is queryable by outfitterId', () {
      final block = _blockFor(_loadRules(), 'outfitter_venison_permits');
      // The outfitter's list query (.where('outfitterId', isEqualTo: uid))
      // succeeds because the rule constrains outfitterId to the caller uid.
      expect(
        block.contains('resource.data.outfitterId == request.auth.uid'),
        isTrue,
      );
    });

    test('the hunter partition is queryable by hunterId', () {
      final block = _blockFor(_loadRules(), 'hunter_venison_permits');
      // The hunter's list query (Filter.or(hunterId == uid, userId == uid))
      // succeeds because the rule constrains both aliases to the caller uid.
      expect(
        block.contains('resource.data.hunterId == request.auth.uid'),
        isTrue,
      );
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
