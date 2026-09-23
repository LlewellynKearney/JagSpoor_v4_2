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

  _purchaseRecordingContracts(rules);

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
  // profile field to `users/{uid}` via `set(merge: true)`. One robust
  // `allow write` grant covers BOTH profile creation and merge-updates for
  // the owner without a permission-denied error. The single restricted
  // field is `deviceFingerprint` (device-level trial-abuse prevention),
  // which stays immutable once set.
  //
  // The server-owned entitlement fields are guarded by CHANGE DETECTION
  // (not key presence) — see the `entitlement fields` group below.
  group('users/{userId} profile write contract (hotfix)', () {
    test('users read = isSignedIn()', () {
      final block = _blockFor(rules, 'users');
      expect(block, contains('allow read: if isSignedIn()'));
    });

    test('users write = owner-scoped signed-in (creation + merge-updates)', () {
      final block = _blockFor(rules, 'users');
      expect(
        block,
        contains('allow write: if isSignedIn() && request.auth.uid == userId'),
      );
      // The old split `allow create` / `allow update` grants were
      // consolidated into the single robust `allow write` grant.
      expect(block, isNot(contains('allow create:')));
      expect(block, isNot(contains('allow update:')));
    });

    test('users write gracefully handles creation (resource-null guard)', () {
      final block = _blockFor(rules, 'users');
      // On create `resource` is null; the guard admits the initial document
      // unconditionally (touching `resource.data` on create would error and
      // silently deny the write).
      expect(block, contains('resource == null'));
    });

    test('users write restricts ONLY deviceFingerprint (immutability kept)', () {
      final block = _blockFor(rules, 'users');
      // The trial-abuse immutability clause must remain intact.
      expect(block, contains("'deviceFingerprint' in resource.data"));
      expect(
        block,
        contains('resource.data.deviceFingerprint == '
            'request.resource.data.deviceFingerprint'),
      );
      // No OTHER field may be frozen in the write grant — the owner must be
      // able to update every profile field (medical info, legal compliance,
      // battery settings, …) without a permission-denied. `deviceFingerprint`
      // is the only immutability clause; `subscriptionStatus` is read on the
      // RESOURCE (stored) side by the v9.2 purchase-confirmation guard, which
      // restricts a transition rather than freezing the field.
      final restrictions = RegExp(r"'([^']+)' in resource\.data")
          .allMatches(block)
          .map((m) => m.group(1))
          .toSet();
      expect(restrictions, {'deviceFingerprint', 'subscriptionStatus'},
          reason: 'deviceFingerprint stays immutable; subscriptionStatus is '
              'only read to validate the Play purchase confirmation');
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

  // ── users/{userId} entitlement-field guard contract ──────────────────────
  //
  // Regression guard for the v8 tester bug: after the signup trial trigger
  // stamps `isPremium` / `subscriptionSource` / `entitlementUpdatedAt` onto
  // users/{uid}, a merge profile save re-sends the complete document, so a
  // KEY-PRESENCE guard (`!('isPremium' in request.resource.data)`) denied the
  // save with PERMISSION_DENIED. The guard must be CHANGE DETECTION: deny only
  // when the submitted value differs from the stored value.
  group('users/{userId} entitlement fields use change detection', () {
    const guardedFields = <String>[
      'isPremium',
      'premiumExpiry',
      'subscriptionSource',
      'subscriptionProduct',
      'subscriptionPlayPurchaseToken',
      'payfastPaymentId',
      'entitlementUpdatedAt',
      // Trial-abuse hardening (v9): the trial window timestamps (every alias
      // the entitlement reader honours), the trial status, the
      // account-creation stamp and the referral-code marker are server-owned —
      // only Cloud Functions (Admin SDK) may write them.
      'trialEndsAt',
      'trialEnd',
      'subscriptionTrialEndsAt',
      'trialStartedAt',
      'trialStart',
      'subscriptionTrialStart',
      'subscriptionStatus',
      'createdAt',
      'referralCodeUsed',
      // v9.2: the convenience premium mirror the Google Play purchase
      // recorder stamps alongside the status confirmation. Guarded so it can
      // only be turned on in the same write that marks the subscription
      // active.
      'isPro',
    ];

    test('no server-owned field is denied by standalone key presence', () {
      final block = _blockFor(rules, 'users');
      for (final field in guardedFields) {
        // A standalone presence deny — `!('F' in request.resource.data)` chained
        // directly with `&&` — is the buggy shape that broke merge saves.
        final standaloneDeny = RegExp(
          "!\\(\\s*'$field'\\s+in\\s+request\\.resource\\.data\\s*\\)\\s*&&",
        );
        expect(
          standaloneDeny.hasMatch(block),
          isFalse,
          reason: "standalone key-presence guard for '$field' reintroduces "
              'the PERMISSION_DENIED merge-save bug',
        );
        // The presence check must instead be an operand of `||`, so it
        // short-circuits to ALLOW when the incoming write omits the field.
        final changeDetection = RegExp(
          "!\\(\\s*'$field'\\s+in\\s+request\\.resource\\.data\\s*\\)\\s*\\|\\|",
        );
        expect(
          changeDetection.hasMatch(block),
          isTrue,
          reason: "'$field' presence check must be paired with a value "
              'comparison via ||',
        );
      }
    });

    test('each server-owned field is compared against the stored value', () {
      final block = _blockFor(rules, 'users');
      for (final field in guardedFields) {
        // Denied only when present AND (no existing doc OR value changed).
        expect(
          block,
          contains("!('$field' in request.resource.data)"),
          reason: "'$field' must still be guarded",
        );
        expect(
          block,
          contains(
            'request.resource.data.$field == resource.data.$field',
          ),
          reason: "'$field' must be change-detected against the stored value",
        );
      }
    });

    test('every guard short-circuits to ALLOW when the field is absent', () {
      final block = _blockFor(rules, 'users');
      // A plain profile save that omits the server-owned fields resolves to
      // `!(false) == true` for each clause, so the write is allowed.
      final guardCount = guardedFields
          .where((f) => block.contains("!('$f' in request.resource.data)"))
          .length;
      expect(guardCount, guardedFields.length);
      // The stored-value comparison must be gated behind `resource != null`
      // so a first-time create (resource == null) that omits the fields is
      // still admitted.
      expect(block, contains('resource != null'));
    });

    test('the guarded field set is exactly the server-owned entitlement set',
        () {
      final block = _blockFor(rules, 'users');
      // Only these fields compare request vs stored; nothing else is frozen
      // (every ordinary profile field stays freely writable by the owner).
      final compared = RegExp(
        r'request\.resource\.data\.(\w+) == resource\.data\.\1',
      ).allMatches(block).map((m) => m.group(1)).toSet();
      expect(compared, guardedFields.toSet());
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
///
/// Line endings are normalized to `\n`: the file is checked out with CRLF on
/// Windows and LF on Unix, and every multi-line `contains` assertion below
/// (plus the brace scanner) assumes `\n`.
String _loadRules() {
  // Run from the project root (flutter test sets the CWD to the package root).
  final file = File('firestore.rules');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

/// Extracts the `match /{col}/{docId} { ... }` block for a collection.
///
/// Walks from the block's opening `{` counting brace depth, so nested
/// `function ... { ... }` declarations (packages, trophy_stock, bookings, …)
/// cannot fool the search for the true closing brace. A naive
/// `indexOf('\n    }\n')` stops at the first nested function's close and
/// fails outright on CRLF line endings.
String _blockFor(String rules, String collection) {
  // Scan the comment-stripped text so a documentation line that mentions a
  // path (e.g. `// ... farm_managers/{uid} lookup`) can never offset the
  // brace count.
  final scan = _stripComments(rules);
  final startPattern =
      RegExp(r'match /' + collection + r'/\{[^}]+\} \{');
  final startMatch = startPattern.firstMatch(scan);
  if (startMatch == null) {
    fail('No match block found for collection $collection');
  }
  final openBrace = startMatch.end - 1; // the `{` that opens the block
  var depth = 0;
  for (var i = openBrace; i < scan.length; i++) {
    final ch = scan[i];
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        return scan.substring(startMatch.start, i + 1);
      }
    }
  }
  fail('No closing brace found for collection $collection block');
}

/// Removes full-line `//` comments from a rules block so assertions test the
/// actual rule code, never documentation. Without this, a comment that merely
/// mentions a guarded field name would satisfy (or break) an assertion.
String _stripComments(String block) {
  return block
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

// ── v9.2: Google Play purchase records + client subscription confirmation ──
//
// `PlayPurchaseRecorder` writes the purchase transaction to
// `purchases/{uid}_{productId}` and mirrors the entitlement onto `users/{uid}`.
// These structural contracts assert the rules permit exactly that and nothing
// broader.
void _purchaseRecordingContracts(String rules) {
  group('purchases collection contract (v9.2)', () {
    test('the purchases match block exists', () {
      expect(rules.contains('match /purchases/{purchaseId}'), isTrue);
    });

    test('reads are owner-scoped to the caller\'s own uid', () {
      final block = _blockFor(rules, 'purchases');
      expect(block, contains('resource.data.uid == request.auth.uid'));
    });

    test('create + update require the caller to own the record', () {
      final block = _blockFor(rules, 'purchases');
      expect(block, contains('request.resource.data.uid == request.auth.uid'));
      expect(block, contains('allow create:'));
      expect(block, contains('allow update:'));
    });

    test('delete is admin-only (a buyer cannot erase the transaction)', () {
      final block = _blockFor(rules, 'purchases');
      expect(block, contains('allow delete: if isAdmin();'));
    });
  });

  group('users/{uid} purchase confirmation contract (v9.2)', () {
    test('subscriptionStatus may move to active from a trial state', () {
      final block = _blockFor(rules, 'users');
      expect(
        block,
        contains("request.resource.data.subscriptionStatus == 'active'"),
      );
      expect(
        block,
        contains("resource.data.subscriptionStatus in ['trialing', 'trial', 'active']"),
      );
    });

    test('isPro may only be set alongside the active confirmation', () {
      final block = _blockFor(rules, 'users');
      expect(block, contains("!('isPro' in request.resource.data)"));
      expect(
        block,
        contains('request.resource.data.isPro == true'),
      );
      expect(
        block,
        contains("request.resource.data.subscriptionStatus == 'active'"),
      );
    });

    test('the subscription-status guard is still a change-detection operand',
        () {
      final block = _blockFor(rules, 'users');
      // The very shape the merge-save bug fix requires: presence checked via
      // `||`, never a standalone `&&` deny.
      expect(
        block,
        contains("!('subscriptionStatus' in request.resource.data)"),
      );
      expect(
        RegExp(r"!\('subscriptionStatus'\s+in\s+request\.resource\.data\s*\)\s*&&")
            .hasMatch(block),
        isFalse,
      );
    });
  });
}
