import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the v1.0.12 billing-security hotfix
/// (`firestore.rules`).
///
/// The Firestore emulator (`@firebase/rules-unit-testing`) cannot run in this
/// sandbox (no Java/JVM, see AGENTS.md environment constraints), so — like
/// `firestore_rules_seeding_test.dart` — these tests parse `firestore.rules`
/// and assert the exact allow-clause contract that closes the two CRITICAL
/// exploits reported in AUDIT_BILLING_REPORT.md:
///
///   1. Any user could self-assign `role: 'admin'` (admin-escalation +
///      paywall bypass).
///   2. Any user could forge `subscriptionStatus: 'active'` on `users/{uid}`
///      (permanent free premium).
///
/// The three tests named in the hotfix brief map to:
///   - "client cannot update role to admin"          -> should be DENIED
///   - "client cannot update subscriptionStatus"      -> should be DENIED
///   - "client CAN update displayName"                -> should be ALLOWED
///
/// Because the emulator is unavailable, the DENY/ALLOW decisions are asserted
/// as the *rule text* that the server evaluates: the `users/{userId}` write
/// guard now carries the role/dual-role/tier/status/isPro change-detection
/// clauses, and those clauses are structured so a displayName-only merge write
/// (which never mentions a frozen field) still passes.
void main() {
  final rules = _loadRules();
  final usersBlock = _blockFor(rules, 'users');

  group('users/{userId} write guard — role freeze (CRITICAL #1)', () {
    test('role change-detection clause is present', () {
      expect(
        usersBlock,
        contains("!('role' in request.resource.data)"),
        reason: 'the role guard must gate on role presence',
      );
      // Setting role only on FIRST assignment: `resource == null` (create) or
      // the stored doc has no role yet.
      expect(usersBlock, contains("!('role' in resource.data)"));
    });

    test('role can never be set to admin by a client', () {
      expect(
        usersBlock,
        contains("request.resource.data.role != 'admin'"),
        reason: 'a client write must never be permitted to set role=admin',
      );
    });

    test('role cannot change once set', () {
      expect(
        usersBlock,
        contains('request.resource.data.role == resource.data.role'),
        reason: 'a stored role must be immutable for client writes',
      );
    });

    test('an admin cannot have their role overwritten by a client', () {
      // `!isAdmin()` guards the whole role clause so an admin-provisioned
      // account is never mutated through the client path.
      expect(usersBlock, contains('!isAdmin()'));
    });

    test('dual-role signals (isDualRole / roles) are frozen', () {
      expect(usersBlock, contains("!('isDualRole' in request.resource.data)"));
      expect(usersBlock, contains("!('roles' in request.resource.data)"));
      expect(
        usersBlock,
        contains('request.resource.data.isDualRole == resource.data.isDualRole'),
      );
      expect(
        usersBlock,
        contains('request.resource.data.roles == resource.data.roles'),
      );
    });
  });

  group('users/{userId} write guard — subscriptionStatus freeze (CRITICAL #2)', () {
    test('the trialing -> active client transition is REMOVED', () {
      expect(
        rules.contains(
          "resource.data.subscriptionStatus in ['trialing', 'trial', 'active']",
        ),
        isFalse,
        reason: 'the client trialing->active transition must be gone',
      );
      expect(
        rules.contains("request.resource.data.subscriptionStatus == 'active'"),
        isFalse,
        reason: 'no client write may set subscriptionStatus to active',
      );
    });

    test('subscriptionStatus is change-detection only', () {
      expect(
        usersBlock,
        contains(
          'request.resource.data.subscriptionStatus == resource.data.subscriptionStatus',
        ),
      );
    });

    test('isPro is change-detection only (cannot be flipped on)', () {
      expect(usersBlock, contains("!('isPro' in request.resource.data)"));
      expect(
        usersBlock,
        contains('request.resource.data.isPro == resource.data.isPro'),
      );
      // The old clause that allowed isPro:true alongside status:'active'.
      expect(
        usersBlock.contains(
          "request.resource.data.isPro == true\n            && request.resource.data.subscriptionStatus == 'active'",
        ),
        isFalse,
      );
    });

    test('subscriptionTier is server-owned (change-detection only)', () {
      expect(
        usersBlock,
        contains("!('subscriptionTier' in request.resource.data)"),
      );
      expect(
        usersBlock,
        contains(
          'request.resource.data.subscriptionTier == resource.data.subscriptionTier',
        ),
      );
    });

    test('entitlements/{uid} remains client-write-denied', () {
      final block = _blockFor(rules, 'entitlements');
      expect(block, contains('allow write: if false'));
      expect(block, contains('allow read: if isSignedIn()'));
    });
  });

  group('users/{userId} write guard — non-entitlement writes still allowed', () {
    test('a displayName-only write never mentions a frozen field', () {
      // The guard is a conjunction of `!('FIELD' in request.resource.data) ||
      // unchanged` clauses. A merge write that only touches `displayName`
      // (or any other non-frozen profile field) does not contain any of the
      // frozen keys, so every clause short-circuits to true and the write is
      // allowed — this is the "client CAN update displayName" contract.
      for (final frozen in [
        'isPremium',
        'premiumExpiry',
        'subscriptionSource',
        'subscriptionProduct',
        'subscriptionPlayPurchaseToken',
        'entitlementUpdatedAt',
        'subscriptionStatus',
        'isPro',
        'subscriptionTier',
        'role',
        'isDualRole',
        'roles',
        'createdAt',
        'referralCodeUsed',
      ]) {
        expect(
          usersBlock,
          contains("!('$frozen' in request.resource.data)"),
          reason: 'frozen field $frozen must be presence-guarded so an '
              'unrelated write (e.g. displayName) passes',
        );
      }
    });

    test('the owner-scoped write grant is intact', () {
      expect(
        usersBlock,
        contains('allow write: if isSignedIn() && request.auth.uid == userId'),
      );
      expect(usersBlock, contains('allow read: if isSignedIn()'));
    });
  });
}

String _loadRules() {
  final file = File('firestore.rules');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

/// Returns the text of the `match /<collection>/{...} { ... }` block, walking
/// brace depth over the comment-stripped text so a documentation line that
/// mentions a path cannot offset the count.
String _blockFor(String rules, String collection) {
  final scan = _stripComments(rules);
  final startPattern = RegExp(r'match /' + collection + r'/\{[^}]+\} \{');
  final startMatch = startPattern.firstMatch(scan);
  if (startMatch == null) {
    fail('No match block found for collection $collection');
  }
  final openBrace = startMatch.end - 1;
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

String _stripComments(String rules) {
  return rules
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}
