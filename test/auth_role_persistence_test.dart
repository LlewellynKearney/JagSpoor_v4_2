// ============================================================================
// Role persistence — AuthRepository contract
//
// The v21 defect: 9 of 25 registered accounts had no `role` on their
// `users/{uid}` document, so they were bounced through "Select Operational
// Profile" on every sign-in. These tests lock the write + verify + self-heal
// contract that closes it, exercised against `FakeFirebaseFirestore` through
// the repository's documented test seam.
// ============================================================================
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/services/auth_repository.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

void main() {
  // Pin the FieldValue platform before any production `FieldValue` is realized.
  FakeFirebaseFirestore();

  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthRepository.firestoreForTesting = fake;
  });

  tearDown(() {
    AuthRepository.resetTestSeams();
  });

  group('AuthRepository.roleFromUserDocument', () {
    test('reads the canonical role', () {
      expect(
        AuthRepository.roleFromUserDocument(const {'role': 'hunter'}),
        AppRole.hunter,
      );
      expect(
        AuthRepository.roleFromUserDocument(const {'role': 'outfitter'}),
        AppRole.outfitter,
      );
    });

    test('detects the dual-role signals', () {
      expect(
        AuthRepository.roleFromUserDocument(const {'isDualRole': true}),
        AppRole.dual,
      );
      expect(
        AuthRepository.roleFromUserDocument(const {
          'roles': ['hunter', 'outfitter'],
        }),
        AppRole.dual,
      );
      expect(
        AuthRepository.roleFromUserDocument(const {'role': 'dual'}),
        AppRole.dual,
      );
    });

    test('collapses missing / unknown / null to unknown', () {
      expect(AuthRepository.roleFromUserDocument(null), AppRole.unknown);
      expect(AuthRepository.roleFromUserDocument(const {}), AppRole.unknown);
      expect(
        AuthRepository.roleFromUserDocument(const {'role': 'unassigned'}),
        AppRole.unknown,
      );
    });
  });

  group('AuthRepository.ensureUserDocument', () {
    test('creates the document when missing, without server-owned fields',
        () async {
      await AuthRepository.instance
          .ensureUserDocument(uid: 'u1', email: 'hunter@example.com');

      final doc = await fake.collection('users').doc('u1').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['uid'], 'u1');
      expect(data['email'], 'hunter@example.com');
      expect(data['onboardingCompleted'], false);
      expect(data['updatedAt'], isNotNull);
      // The create payload must stay clear of the fields firestore.rules
      // freezes — writing any of them would deny the whole create.
      for (final field in AuthRepository.serverOwnedFields) {
        expect(data.containsKey(field), isFalse,
            reason: '$field must not be client-written');
      }
    });

    test('backfills a missing email on an existing document', () async {
      await fake.collection('users').doc('u2').set({'role': 'hunter'});
      await AuthRepository.instance
          .ensureUserDocument(uid: 'u2', email: 'late@example.com');

      final data = (await fake.collection('users').doc('u2').get()).data()!;
      expect(data['email'], 'late@example.com');
      expect(data['role'], 'hunter'); // untouched
    });

    test('is a no-op for an existing document that already has an email',
        () async {
      await fake
          .collection('users')
          .doc('u3')
          .set({'email': 'kept@example.com', 'role': 'outfitter'});
      await AuthRepository.instance
          .ensureUserDocument(uid: 'u3', email: 'different@example.com');
      final data = (await fake.collection('users').doc('u3').get()).data()!;
      expect(data['email'], 'kept@example.com');
    });

    test('returns false for an empty uid without touching Firestore', () async {
      expect(
        await AuthRepository.instance.ensureUserDocument(uid: ''),
        isFalse,
      );
    });
  });

  group('AuthRepository.hasRole / storedRole', () {
    test('false when the document is missing', () async {
      expect(await AuthRepository.instance.hasRole('ghost'), isFalse);
      expect(await AuthRepository.instance.storedRole('ghost'), AppRole.unknown);
    });

    test('false when the document exists without a role', () async {
      await fake.collection('users').doc('u4').set({'email': 'a@b.c'});
      expect(await AuthRepository.instance.hasRole('u4'), isFalse);
    });

    test('true once a role is stored', () async {
      await fake.collection('users').doc('u5').set({'role': 'outfitter'});
      expect(await AuthRepository.instance.hasRole('u5'), isTrue);
      expect(
        await AuthRepository.instance.storedRole('u5'),
        AppRole.outfitter,
      );
    });
  });

  group('AuthRepository.saveRole', () {
    test('writes the role + onboarding flags and verifies the write',
        () async {
      await AuthRepository.instance.saveRole(uid: 'u6', role: 'hunter');

      final data = (await fake.collection('users').doc('u6').get()).data()!;
      expect(data['role'], 'hunter');
      expect(data['onboardingCompleted'], isTrue);
      expect(data['roleSelectedAt'], isNotNull);
      expect(data['roleSetAt'], isNotNull); // legacy alias kept in sync
      expect(data['updatedAt'], isNotNull);
    });

    test('preserves unrelated profile fields (merge write)', () async {
      await fake
          .collection('users')
          .doc('u7')
          .set({'email': 'keep@me.com', 'firstName': 'Jan'});
      await AuthRepository.instance.saveRole(uid: 'u7', role: 'outfitter');

      final data = (await fake.collection('users').doc('u7').get()).data()!;
      expect(data['role'], 'outfitter');
      expect(data['email'], 'keep@me.com');
      expect(data['firstName'], 'Jan');
    });

    test('normalizes the role casing', () async {
      await AuthRepository.instance.saveRole(uid: 'u8', role: '  HUNTER  ');
      final data = (await fake.collection('users').doc('u8').get()).data()!;
      expect(data['role'], 'hunter');
    });

    test('rejects an unsupported role (never writes admin)', () async {
      await expectLater(
        AuthRepository.instance.saveRole(uid: 'u9', role: 'admin'),
        throwsA(isA<AuthRolePersistenceException>()),
      );
      final doc = await fake.collection('users').doc('u9').get();
      expect(doc.exists, isFalse);
    });

    test('rejects an empty uid', () async {
      await expectLater(
        AuthRepository.instance.saveRole(uid: '', role: 'hunter'),
        throwsA(isA<AuthRolePersistenceException>()),
      );
    });

    test('throws when the role cannot be confirmed after saving', () async {
      // A read-back that never sees a role simulates a write that silently
      // does not persist — the exact defect being fixed. The write itself
      // succeeds against the fake, so this isolates the verification step.
      AuthRepository.roleReadbackForTesting = (_) async => AppRole.unknown;
      await expectLater(
        AuthRepository.instance.saveRole(uid: 'u10', role: 'hunter'),
        throwsA(isA<AuthRolePersistenceException>()),
      );
    });
  });

  group('role selection end-to-end (Firestore contract)', () {
    test('new user -> select role -> doc carries role + flags', () async {
      const uid = 'new-user';
      // Signup only wrote the email (the Auth onCreate trigger owns createdAt).
      await fake.collection('users').doc(uid).set({'email': 'n@u.com'});

      await AuthRepository.instance
          .ensureUserDocument(uid: uid, email: 'n@u.com');
      await AuthRepository.instance.saveRole(uid: uid, role: 'hunter');

      final data = (await fake.collection('users').doc(uid).get()).data()!;
      expect(data['role'], 'hunter');
      expect(data['onboardingCompleted'], isTrue);
      // Re-open: the role resolves, so routing skips role selection.
      expect(await AuthRepository.instance.hasRole(uid), isTrue);
    });

    test('self-heals an account with no document at all', () async {
      const uid = 'doc-less';
      expect(await AuthRepository.instance.hasRole(uid), isFalse);
      await AuthRepository.instance
          .ensureUserDocument(uid: uid, email: 'ghost@u.com');
      await AuthRepository.instance.saveRole(uid: uid, role: 'outfitter');
      expect(await AuthRepository.instance.hasRole(uid), isTrue);
    });
  });
}
