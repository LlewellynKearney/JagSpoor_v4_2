// ============================================================================
// Role selection screen — persistence flow
//
// The reported onboarding defect: the role screen did not persist the choice,
// so 9 of 25 accounts were bounced back to it on every sign-in. These widget
// tests drive the real screen against a `FakeFirebaseFirestore` and assert the
// document contract that makes the choice stick.
// ============================================================================
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/admin/services/admin_auth_guard.dart';
import 'package:jagspoor/features/auth/role_selection_screen.dart';
import 'package:jagspoor/features/auth/services/auth_repository.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

void main() {
  // Pin the FieldValue platform before any production `FieldValue` is realized.
  FakeFirebaseFirestore();

  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthRepository.firestoreForTesting = fake;
    // The role screen re-checks the admin guard on tap; pin it to non-admin so
    // the single-role confirmation flow runs.
    AdminAuthGuard.adminOverrideForTesting = false;
    UserRoleProvider.instance.reset();
  });

  tearDown(() {
    AuthRepository.resetTestSeams();
    AdminAuthGuard.resetTestSeams();
    UserRoleProvider.instance.reset();
  });

  /// Pumps the role screen with a route table so navigation is observable.
  Future<void> pumpRoleScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const RoleSelectionScreen(),
      routes: {
        '/hunter_dashboard': (_) => const Scaffold(body: Text('HUNTER HOME')),
        '/outfitter_dashboard': (_) =>
            const Scaffold(body: Text('OUTFITTER HOME')),
      },
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the two role choices', (tester) async {
    AuthRepository.currentUserForTesting = (uid: 'uid-a', email: 'a@b.c');
    await pumpRoleScreen(tester);

    expect(find.text('HUNTER MODE'), findsOneWidget);
    expect(find.text('OUTFITTER MODE'), findsOneWidget);
    expect(find.text('HUNTER HOME'), findsNothing);
  });

  testWidgets('confirming Outfitter persists the role and navigates onward',
      (tester) async {
    AuthRepository.currentUserForTesting = (uid: 'uid-b', email: 'b@b.c');
    await pumpRoleScreen(tester);

    // Tap the Outfitter card, then confirm in the exclusivity dialog.
    await tester.tap(find.text('OUTFITTER MODE'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Operational Role'), findsOneWidget);
    await tester.tap(find.text('Confirm & Proceed'));
    await tester.pumpAndSettle();

    // The role is in Firestore — the whole point of the fix.
    final data = (await fake.collection('users').doc('uid-b').get()).data()!;
    expect(data['role'], 'outfitter');
    expect(data['onboardingCompleted'], isTrue);
    expect(data['updatedAt'], isNotNull);

    // ...and the screen moved on rather than staying put.
    expect(find.text('OUTFITTER HOME'), findsOneWidget);
    expect(
      UserRoleProvider.instance.role,
      AppRole.outfitter,
      reason: 'the chosen role must be cached for the destination route guard',
    );
  });

  testWidgets(
      'a role-bearing account is bounced straight to its dashboard '
      '(no re-selection on sign-in)', (tester) async {
    // Simulates the close/reopen case: the account already has a role.
    await fake.collection('users').doc('uid-c').set({'role': 'hunter'});
    AuthRepository.currentUserForTesting = (uid: 'uid-c', email: 'c@b.c');

    await pumpRoleScreen(tester);

    expect(find.text('HUNTER HOME'), findsOneWidget);
    // The selection UI is gone.
    expect(find.text('HUNTER MODE'), findsNothing);
  });

  testWidgets('a dual-role account is routed to the hunter dashboard',
      (tester) async {
    await fake.collection('users').doc('uid-d').set({
      'isDualRole': true,
      'roles': ['hunter', 'outfitter'],
    });
    AuthRepository.currentUserForTesting = (uid: 'uid-d', email: 'd@b.c');

    await pumpRoleScreen(tester);
    expect(find.text('HUNTER HOME'), findsOneWidget);
  });

  testWidgets('a signed-out caller stays on the screen', (tester) async {
    AuthRepository.currentUserForTesting = (uid: '', email: null);
    await pumpRoleScreen(tester);

    expect(find.text('HUNTER HOME'), findsNothing);
    expect(find.text('OUTFITTER HOME'), findsNothing);
    expect(find.text('HUNTER MODE'), findsOneWidget);
  });
}
