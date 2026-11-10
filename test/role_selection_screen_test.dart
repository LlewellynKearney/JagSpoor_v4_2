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
    UserRoleProvider.instance.reset();
  });

  tearDown(() {
    AuthRepository.resetTestSeams();
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
        '/admin_dashboard': (_) => const Scaffold(body: Text('ADMIN HOME')),
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

  testWidgets('never renders an Admin Portal card (admin is not UI-selectable)',
      (tester) async {
    AuthRepository.currentUserForTesting = (uid: 'uid-adm', email: 'a@b.c');
    await pumpRoleScreen(tester);

    // The admin role is granted out-of-band only — there is NO UI path to it.
    expect(find.text('ADMIN PORTAL'), findsNothing);
    expect(find.text('ADMIN HOME'), findsNothing);
    // Exactly the two self-selectable roles are offered.
    expect(find.text('HUNTER MODE'), findsOneWidget);
    expect(find.text('OUTFITTER MODE'), findsOneWidget);
  });

  testWidgets('the body is scrollable and does not overflow at 1.3x text scale',
      (tester) async {
    AuthRepository.currentUserForTesting = (uid: 'uid-scale', email: 'a@b.c');
    // Small phone + enlarged text — the layout that used to RenderFlex-overflow.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: const RoleSelectionScreen(),
      ),
      routes: {
        '/hunter_dashboard': (_) => const Scaffold(body: Text('HUNTER HOME')),
        '/outfitter_dashboard': (_) =>
            const Scaffold(body: Text('OUTFITTER HOME')),
      },
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    // No RenderFlex overflow / layout exception.
    expect(tester.takeException(), isNull);
    expect(find.text('HUNTER MODE'), findsOneWidget);
    expect(find.text('OUTFITTER MODE'), findsOneWidget);
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

  testWidgets(
      'a stored admin role is bounced to the admin dashboard — never offered '
      'admin selection UI', (tester) async {
    await fake.collection('users').doc('uid-admin').set({'role': 'admin'});
    AuthRepository.currentUserForTesting =
        (uid: 'uid-admin', email: 'admin@jag-spoor.co.za');

    await pumpRoleScreen(tester);

    // Routed onward by _skipIfRoleAlreadyAssigned (admin is never selectable).
    expect(find.text('ADMIN HOME'), findsOneWidget);
    expect(find.text('ADMIN PORTAL'), findsNothing);
    expect(find.text('HUNTER MODE'), findsNothing);
  });

  testWidgets(
      'a fast double-tap opens only ONE confirmation dialog (no double write)',
      (tester) async {
    AuthRepository.currentUserForTesting = (uid: 'uid-race', email: 'r@b.c');
    await pumpRoleScreen(tester);

    // Two taps in the same frame — the `_saving` guard (set BEFORE the dialog
    // opens) must swallow the second. The second tap is now covered by the
    // modal barrier, so warnIfMissed is disabled (the miss IS the guard).
    await tester.tap(find.text('OUTFITTER MODE'));
    await tester.tap(find.text('OUTFITTER MODE'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Operational Role'), findsOneWidget);
    // Cancelling releases the guard so the user can pick again.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Operational Role'), findsNothing);
    expect(find.text('OUTFITTER MODE'), findsOneWidget);
  });
}
