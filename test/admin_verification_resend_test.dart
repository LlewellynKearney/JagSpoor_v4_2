import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';
import 'package:jagspoor/features/admin/models/admin_verification_target.dart';
import 'package:jagspoor/features/admin/services/admin_verification_resend_service.dart';
import 'package:jagspoor/features/admin/widgets/admin_verification_card.dart';
import 'package:jagspoor/features/auth/services/email_verification_service.dart';

/// Bug fix — email verification send tracking + admin resend.
///
/// Covers:
///  * the `EmailVerificationService` audit trail (a failed send records the
///    flag on `users/{uid}`);
///  * the pure `AdminVerificationTarget` TWO-BUCKET split (no-role = resend
///    targets; with-role = reminder only) + the batch cap;
///  * the admin card: the no-role resend button calls the service, the bulk
///    action respects the 50-per-batch cap, the with-role reminder opens a
///    mailto, and a non-admin cannot trigger any of it.
void main() {
  group('EmailVerificationService audit trail', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
      EmailVerificationService.instance.resetTestSeams();
    });

    tearDown(() => EmailVerificationService.instance.resetTestSeams());

    test('a failed send records verificationEmailSent=false + the error',
        () async {
      final svc = EmailVerificationService.instance;
      svc.firestoreForTesting = db;
      svc.currentUserIdResolverForTesting = () => 'user-1';
      svc.sendOverride = () async {
        throw StateError('network down');
      };

      await expectLater(
        svc.sendVerificationEmail(),
        throwsA(isA<StateError>()),
      );

      final doc = await db.collection('users').doc('user-1').get();
      final data = doc.data()!;
      expect(data[EmailVerificationService.sentField], isFalse);
      expect(
        data[EmailVerificationService.lastErrorField],
        contains('network down'),
      );
      expect(
        data[EmailVerificationService.lastAttemptField],
        isNotNull,
      );
    });

    test('a successful send records verificationEmailSent=true', () async {
      final svc = EmailVerificationService.instance;
      svc.firestoreForTesting = db;
      svc.currentUserIdResolverForTesting = () => 'user-2';
      svc.sendOverride = () async {};

      await svc.sendVerificationEmail();

      final data = (await db.collection('users').doc('user-2').get()).data()!;
      expect(data[EmailVerificationService.sentField], isTrue);
      // A success clears any prior error marker.
      expect(data.containsKey(EmailVerificationService.lastErrorField), isFalse);
    });

    test('no signed-in user is a silent no-op (never throws)', () async {
      final svc = EmailVerificationService.instance;
      svc.firestoreForTesting = db;
      svc.currentUserIdResolverForTesting = () => null;
      svc.sendOverride = () async {
        throw StateError('should not be called');
      };

      await svc.sendVerificationEmail();
      // No users doc is created.
      final all = await db.collection('users').get();
      expect(all.docs, isEmpty);
    });
  });

  group('AdminVerificationTarget two-bucket split', () {
    test('missedVerification is unverified AND no successful send', () {
      expect(
        const AdminVerificationTarget(uid: 'a', emailVerified: false)
            .missedVerification,
        isTrue,
      );
      expect(
        const AdminVerificationTarget(
          uid: 'b',
          emailVerified: false,
          verificationEmailSent: true,
        ).missedVerification,
        isFalse,
      );
      expect(
        const AdminVerificationTarget(uid: 'c', emailVerified: true)
            .missedVerification,
        isFalse,
      );
    });

    test('hasRole treats blank / none / unassigned / unknown as no role', () {
      expect(const AdminVerificationTarget(uid: 'a').hasRole, isFalse);
      expect(const AdminVerificationTarget(uid: 'a', role: '  ').hasRole,
          isFalse);
      expect(const AdminVerificationTarget(uid: 'a', role: 'none').hasRole,
          isFalse);
      expect(const AdminVerificationTarget(uid: 'a', role: 'UNASSIGNED').hasRole,
          isFalse);
      expect(const AdminVerificationTarget(uid: 'a', role: 'unknown').hasRole,
          isFalse);
      expect(
          const AdminVerificationTarget(uid: 'a', role: 'hunter').hasRole,
          isTrue);
      expect(
          const AdminVerificationTarget(uid: 'a', role: 'Outfitter').hasRole,
          isTrue);
    });

    test('the buckets are disjoint and partition the unverified set', () {
      const noRole = AdminVerificationTarget(uid: 'n');
      const withRole = AdminVerificationTarget(uid: 'w', role: 'hunter');
      const verified = AdminVerificationTarget(uid: 'v', emailVerified: true);
      const sent = AdminVerificationTarget(uid: 's', verificationEmailSent: true);

      expect(noRole.missedNoRole, isTrue);
      expect(noRole.unverifiedWithRole, isFalse);
      expect(withRole.missedNoRole, isFalse);
      expect(withRole.unverifiedWithRole, isTrue);
      // Verified / already-sent are in NEITHER bucket.
      expect(verified.missedNoRole, isFalse);
      expect(verified.unverifiedWithRole, isFalse);
      expect(sent.missedNoRole, isFalse);
      expect(sent.unverifiedWithRole, isFalse);
    });

    test('statusLabel reflects verified / sent / failed / never sent', () {
      expect(
        const AdminVerificationTarget(uid: 'a', emailVerified: true).statusLabel,
        'Verified',
      );
      expect(
        const AdminVerificationTarget(uid: 'a', verificationEmailSent: true)
            .statusLabel,
        'Sent',
      );
      expect(
        const AdminVerificationTarget(
          uid: 'a',
          verificationEmailLastError: 'EAUTH',
        ).statusLabel,
        'Failed',
      );
      expect(
        const AdminVerificationTarget(uid: 'a').statusLabel,
        'Never sent',
      );
    });

    test('fromMap parses the audit fields + role + a Timestamp attempt', () {
      final t = AdminVerificationTarget.fromMap('uid-1', {
        'email': 'Hunter@Example.com ',
        'role': 'hunter',
        'emailVerified': false,
        'verificationEmailSent': false,
        'verificationEmailLastError': 'auth/too-many-requests',
        'verificationEmailLastAttemptAt':
            Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
      });
      expect(t.email, 'hunter@example.com');
      expect(t.role, 'hunter');
      expect(t.emailVerified, isFalse);
      expect(t.lastAttemptFailed, isTrue);
      expect(t.missedVerification, isTrue);
      expect(t.unverifiedWithRole, isTrue);
      expect(t.missedNoRole, isFalse);
      expect(t.verificationEmailLastAttemptAt, isNotNull);
    });

    test('missing audit fields default to never-sent / unverified / no role', () {
      final t = AdminVerificationTarget.fromMap('uid-2', null);
      expect(t.emailVerified, isFalse);
      expect(t.verificationEmailSent, isFalse);
      expect(t.hasRole, isFalse);
      expect(t.missedNoRole, isTrue);
      expect(t.unverifiedWithRole, isFalse);
      expect(t.statusLabel, 'Never sent');
    });
  });

  group('adminVerificationResendBatch (rate limit, no-role only)', () {
    List<AdminVerificationTarget> manyNoRole(int n) => [
          for (var i = 0; i < n; i++)
            AdminVerificationTarget(uid: 'u$i', emailVerified: false),
        ];

    test('returns all no-role users when under the limit', () {
      expect(adminVerificationResendBatch(manyNoRole(3)).length, 3);
    });

    test('caps the batch at the limit (50)', () {
      expect(kAdminVerificationResendBatchLimit, 50);
      expect(adminVerificationResendBatch(manyNoRole(120)).length, 50);
    });

    test('NEVER includes role-bearing or verified accounts', () {
      final batch = adminVerificationResendBatch([
        const AdminVerificationTarget(uid: 'verified', emailVerified: true),
        const AdminVerificationTarget(uid: 'unverified-no-role'),
        const AdminVerificationTarget(uid: 'unverified-with-role', role: 'hunter'),
      ]);
      expect(batch.map((t) => t.uid), ['unverified-no-role']);
    });

    test('a custom limit is honoured', () {
      expect(adminVerificationResendBatch(manyNoRole(10), limit: 4).length, 4);
    });
  });

  group('AdminVerificationCard (widget)', () {
    AdminUserRecord rec(
      String uid, {
      bool verified = false,
      bool sent = false,
      String role = '',
    }) =>
        AdminUserRecord(
          uid: uid,
          email: '$uid@example.com',
          role: role,
          emailVerified: verified,
          verificationEmailSent: sent,
        );

    Widget build({
      required List<AdminUserRecord> records,
      bool isAdmin = true,
      Future<ResendOutcome> Function(String)? resendOne,
      Future<BulkResendOutcome> Function(List<String>)? resendBulk,
      Future<bool> Function(Uri)? launchReminder,
    }) {
      final theme = ThemeController();
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminVerificationCard(
              theme: theme,
              records: records,
              isAdmin: isAdmin,
              resendOneOverride: resendOne,
              resendBulkOverride: resendBulk,
              launchReminderOverride: launchReminder,
            ),
          ),
        ),
      );
    }

    testWidgets('shows BOTH counts (no single 72-style button)', (tester) async {
      await tester.pumpWidget(build(records: [
        rec('n1'), // no role
        rec('n2'), // no role
        rec('w1', role: 'hunter'), // with role
        rec('sent', sent: true), // already sent -> neither
      ]));
      expect(find.text('No Role (2)'), findsOneWidget);
      expect(find.text('Unverified With Role (1)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adminV2ResendNoRoleButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adminV2RemindWithRoleButton')),
        findsOneWidget,
      );
      // The old single "Resend to All Unverified" button is gone.
      expect(
        find.byKey(const ValueKey('adminV2ResendAllUnverifiedButton')),
        findsNothing,
      );
      // The already-sent account appears in neither list.
      expect(find.byKey(const ValueKey('adminV2ResendRow_sent')), findsNothing);
    });

    testWidgets('the per-row resend button calls the service', (tester) async {
      final called = <String>[];
      await tester.pumpWidget(build(
        records: [rec('n1')],
        resendOne: (uid) async {
          called.add(uid);
          return const ResendOutcome(delivered: true, message: 'sent');
        },
      ));
      await tester.tap(find.byKey(const ValueKey('adminV2ResendRow_n1')));
      await tester.pumpAndSettle();
      expect(called, ['n1']);
    });

    testWidgets('the no-role bulk action confirms then resends the capped batch',
        (tester) async {
      // 30 no-role + 20 with-role = the bulk must only ever send the no-role
      // ones (and never the role-bearing accounts).
      final records = [
        for (var i = 0; i < 30; i++) rec('n$i'),
        for (var i = 0; i < 20; i++) rec('w$i', role: 'hunter'),
      ];
      List<String>? sentUids;
      await tester.pumpWidget(build(
        records: records,
        resendBulk: (uids) async {
          sentUids = uids;
          return BulkResendOutcome(
            delivered: uids.length,
            processed: uids.length,
            skipped: 0,
            message: 'ok',
          );
        },
      ));
      await tester.tap(
          find.byKey(const ValueKey('adminV2ResendNoRoleButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resend to 30 no-role users?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adminV2ConfirmBulkResend')));
      await tester.pumpAndSettle();
      expect(sentUids, isNotNull);
      expect(sentUids!.length, 30);
      // Every uid sent is a no-role uid.
      expect(sentUids!.every((u) => u.startsWith('n')), isTrue);
    });

    testWidgets('the no-role bulk action caps at the limit', (tester) async {
      final records = [for (var i = 0; i < 60; i++) rec('n$i')];
      List<String>? sentUids;
      await tester.pumpWidget(build(
        records: records,
        resendBulk: (uids) async {
          sentUids = uids;
          return BulkResendOutcome(
            delivered: uids.length,
            processed: uids.length,
            skipped: 60 - uids.length,
            message: 'ok',
          );
        },
      ));
      await tester.tap(
          find.byKey(const ValueKey('adminV2ResendNoRoleButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adminV2ConfirmBulkResend')));
      await tester.pumpAndSettle();
      expect(sentUids!.length, kAdminVerificationResendBatchLimit);
    });

    testWidgets('the with-role reminder opens a mailto (never a resend)',
        (tester) async {
      Uri? launched;
      await tester.pumpWidget(build(
        records: [rec('w1', role: 'hunter'), rec('w2', role: 'outfitter')],
        launchReminder: (uri) async {
          launched = uri;
          return true;
        },
      ));
      await tester.tap(
          find.byKey(const ValueKey('adminV2RemindWithRoleButton')));
      await tester.pumpAndSettle();
      expect(launched, isNotNull);
      expect(launched!.scheme, 'mailto');
      final q = launched!.query;
      expect(q, contains('w1%40example.com'));
      expect(q, contains('w2%40example.com'));
      expect(q, contains('subject='));
      // It must NOT be a verification-link send.
      expect(launched!.path, 'support@jag-spoor.co.za');
    });

    testWidgets('the no-role bulk action surfaces a server diagnostic (not "0 of 0")',
        (tester) async {
      // The server returns failed-precondition with the actionable diagnostic
      // when EVERY attempt was denied for IAM reasons. The card must show that
      // diagnostic — the old code showed a bare "Resent to 0 of 0." which hid
      // the real problem.
      const diagnostic =
          'Auth Admin call rejected: the credential has insufficient '
          'permission. Identity: 475471855344-compute@developer.gserviceaccount.com '
          '(source: computeMetadata). Grant roles/firebaseauth.admin to this '
          'service account.';
      await tester.pumpWidget(build(
        records: [rec('n1'), rec('n2')],
        resendBulk: (uids) async => const BulkResendOutcome(
          delivered: 0,
          processed: 0,
          skipped: 0,
          message: diagnostic,
        ),
      ));
      await tester.tap(
          find.byKey(const ValueKey('adminV2ResendNoRoleButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adminV2ConfirmBulkResend')));
      await tester.pumpAndSettle();
      expect(find.textContaining('roles/firebaseauth.admin'), findsOneWidget);
      expect(
        find.textContaining('475471855344-compute@developer.gserviceaccount.com'),
        findsOneWidget,
      );
      expect(find.textContaining('0 of 0'), findsNothing);
    });

    testWidgets('a successful no-role bulk resend reports the delivered count',
        (tester) async {
      await tester.pumpWidget(build(
        records: [rec('n1'), rec('n2')],
        resendBulk: (uids) async => BulkResendOutcome(
          delivered: uids.length,
          processed: uids.length,
          skipped: 0,
          message: 'ok',
        ),
      ));
      await tester.tap(
          find.byKey(const ValueKey('adminV2ResendNoRoleButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adminV2ConfirmBulkResend')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resent to 2 of 2'), findsOneWidget);
    });

    testWidgets('a non-admin sees the counts but every action is disabled',
        (tester) async {
      await tester.pumpWidget(build(
        records: [rec('n1'), rec('w1', role: 'hunter')],
        isAdmin: false,
      ));
      final bulk = tester.widget<FilledButton>(
          find.byKey(const ValueKey('adminV2ResendNoRoleButton')));
      expect(bulk.onPressed, isNull);
      final remind = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('adminV2RemindWithRoleButton')));
      expect(remind.onPressed, isNull);
      final row = tester.widget<TextButton>(
          find.byKey(const ValueKey('adminV2ResendRow_n1')));
      expect(row.onPressed, isNull);
      expect(find.textContaining('Admin only'), findsOneWidget);
    });
  });

  group('AdminVerificationResendService error surfacing', () {
    tearDown(() => AdminVerificationResendService.resetTestSeams());

    test('a failed-precondition diagnostic is surfaced verbatim (not "0 of N")',
        () {
      final body = jsonEncode({
        'error': {
          'status': 'FAILED_PRECONDITION',
          'message':
              'Auth Admin call rejected: the credential has insufficient '
              'permission. Identity: firebase-adminsdk-fbsvc@jagspoor.'
              'iam.gserviceaccount.com (source: computeMetadata). '
              'Grant roles/firebaseauth.admin to this service account.',
        },
      });
      final msg = AdminVerificationResendService.errorMessageFor(
        http.Response(body, 400),
        'Bulk resend failed (400).',
      );
      expect(msg, contains('roles/firebaseauth.admin'));
      expect(msg, contains('firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com'));
      expect(msg, isNot(contains('0 of')));
    });

    test('falls back when the body carries no callable error message', () {
      expect(
        AdminVerificationResendService.errorMessageFor(
          http.Response('not json', 500),
          'Bulk resend failed (500).',
        ),
        'Bulk resend failed (500).',
      );
      expect(
        AdminVerificationResendService.errorMessageFor(
          http.Response(jsonEncode({'error': {'message': '   '}}), 500),
          'fallback',
        ),
        'fallback',
      );
    });
  });
}
