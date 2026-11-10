// ============================================================================
// Role-selection route guard — `/role_selection` is gated (v4.2.26).
//
// The route was previously reachable unguarded (a direct `#/role_selection`
// hit on web let an unverified account pick a role, and a role-bearing account
// re-enter selection). These tests drive the real `RoleGuardedRoute` in its
// `roleSelectionGate` mode:
//   * unverified  -> the email-verification gate is pushed
//   * verified + no role -> the RoleSelectionScreen mounts
//   * verified + role assigned -> bounced to that role's default home
// ============================================================================
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/role_selection_screen.dart';
import 'package:jagspoor/features/auth/screens/email_verification_screen.dart';
import 'package:jagspoor/features/auth/services/auth_repository.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';
import 'package:jagspoor/features/auth/widgets/role_guarded_route.dart';

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
    RoleGuardedRoute.emailVerificationRequiredForTesting = null;
  });

  Widget guarded() => MaterialApp(
        home: RoleGuardedRoute(
          route: '/role_selection',
          roleSelectionGate: true,
          builder: (_) => const RoleSelectionScreen(),
        ),
        routes: {
          '/hunter_dashboard': (_) => const Scaffold(body: Text('HUNTER HOME')),
          '/outfitter_dashboard': (_) =>
              const Scaffold(body: Text('OUTFITTER HOME')),
          '/admin_dashboard': (_) => const Scaffold(body: Text('ADMIN HOME')),
        },
      );

  testWidgets('an unverified account is sent to the email-verification gate',
      (tester) async {
    UserRoleProvider.instance.injectForTesting(db: fake, testUid: 'uid-unver');
    AuthRepository.currentUserForTesting = (uid: 'uid-unver', email: 'u@b.c');
    RoleGuardedRoute.emailVerificationRequiredForTesting = () async => true;

    await tester.pumpWidget(guarded());
    // The gate owns a periodic poll timer, so pump a bounded number of frames
    // rather than pumpAndSettle (which would never settle).
    await tester.pump();
    await tester.pump();

    expect(find.byType(EmailVerificationScreen), findsOneWidget);
    // The role-selection UI never mounted.
    expect(find.text('HUNTER MODE'), findsNothing);
  });

  testWidgets('a verified account with no role sees the role selector',
      (tester) async {
    UserRoleProvider.instance.injectForTesting(db: fake, testUid: 'uid-new');
    AuthRepository.currentUserForTesting = (uid: 'uid-new', email: 'n@b.c');
    RoleGuardedRoute.emailVerificationRequiredForTesting = () async => false;

    await tester.pumpWidget(guarded());
    await tester.pumpAndSettle();

    expect(find.text('HUNTER MODE'), findsOneWidget);
    expect(find.text('OUTFITTER MODE'), findsOneWidget);
    expect(find.byType(EmailVerificationScreen), findsNothing);
  });

  testWidgets('a role-bearing account is bounced off the selector to its home',
      (tester) async {
    await fake.collection('users').doc('uid-hunter').set({'role': 'hunter'});
    UserRoleProvider.instance.injectForTesting(db: fake, testUid: 'uid-hunter');
    AuthRepository.currentUserForTesting = (uid: 'uid-hunter', email: 'h@b.c');
    RoleGuardedRoute.emailVerificationRequiredForTesting = () async => false;

    await tester.pumpWidget(guarded());
    await tester.pumpAndSettle();

    expect(find.text('HUNTER HOME'), findsOneWidget);
    expect(find.text('HUNTER MODE'), findsNothing);
  });
}
