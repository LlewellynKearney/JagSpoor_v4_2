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
    test('animals: read = true (public game guide)', () {
      final block = _blockFor(rules, 'animals');
      expect(block, contains('allow read: if true;'));
      // Animals are NOT seeded at startup (seedAnimalsFromCSV is a manual
      // admin utility), so write stays admin-only.
      expect(block, contains('allow write: if isAdmin()'));
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
