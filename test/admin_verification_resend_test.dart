import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
///  * the pure `AdminVerificationTarget` / batch-limit contract;
///  * the admin card: the resend button calls the service, the bulk action
///    respects the 50-per-batch cap, and a non-admin cannot trigger either.
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
        EmailVerificationService.instance.sendVerificationEmail(),
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

      await EmailVerificationService.instance.sendVerificationEmail();

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

      await EmailVerificationService.instance.sendVerificationEmail();
      // No users doc is created.
      final all = await db.collection('users').get();
      expect(all.docs, isEmpty);
    });
  });

  group('AdminVerificationTarget', () {
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

    test('fromMap parses the audit fields + a Timestamp attempt', () {
      final t = AdminVerificationTarget.fromMap('uid-1', {
        'email': 'Hunter@Example.com ',
        'emailVerified': false,
        'verificationEmailSent': false,
        'verificationEmailLastError': 'auth/too-many-requests',
        'verificationEmailLastAttemptAt':
            Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
      });
      expect(t.email, 'hunter@example.com');
      expect(t.emailVerified, isFalse);
      expect(t.lastAttemptFailed, isTrue);
      expect(t.missedVerification, isTrue);
      expect(t.verificationEmailLastAttemptAt, isNotNull);
    });

    test('missing audit fields default to never-sent / unverified', () {
      final t = AdminVerificationTarget.fromMap('uid-2', null);
      expect(t.emailVerified, isFalse);
      expect(t.verificationEmailSent, isFalse);
      expect(t.missedVerification, isTrue);
      expect(t.statusLabel, 'Never sent');
    });
  });

  group('adminVerificationResendBatch (rate limit)', () {
    List<AdminVerificationTarget> many(int n) => [
          for (var i = 0; i < n; i++)
            AdminVerificationTarget(uid: 'u$i', emailVerified: false),
        ];

    test('returns all missed users when under the limit', () {
      final batch = adminVerificationResendBatch(many(3));
      expect(batch.length, 3);
    });

    test('caps the batch at the limit (50)', () {
      expect(kAdminVerificationResendBatchLimit, 50);
      final batch = adminVerificationResendBatch(many(120));
      expect(batch.length, 50);
    });

    test('only includes unverified accounts', () {
      final batch = adminVerificationResendBatch([
        const AdminVerificationTarget(uid: 'verified', emailVerified: true),
        const AdminVerificationTarget(uid: 'unverified'),
      ]);
      expect(batch.map((t) => t.uid), ['unverified']);
    });

    test('a custom limit is honoured', () {
      expect(adminVerificationResendBatch(many(10), limit: 4).length, 4);
    });
  });

  group('AdminVerificationCard (widget)', () {
    AdminUserRecord rec(String uid, {bool verified = false, bool sent = false}) =>
        AdminUserRecord(
          uid: uid,
          email: '$uid@example.com',
          emailVerified: verified,
          verificationEmailSent: sent,
        );

    Widget build({
      required List<AdminUserRecord> records,
      bool isAdmin = true,
      Future<ResendOutcome> Function(String)? resendOne,
      Future<BulkResendOutcome> Function(List<String>)? resendBulk,
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
            ),
          ),
        ),
      );
    }

    testWidgets('renders the unverified count and per-row RESEND', (tester) async {
      await tester.pumpWidget(build(records: [rec('a'), rec('b', sent: true)]));
      expect(find.textContaining('Email Verification (1 unverified)'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2ResendRow_a')), findsOneWidget);
      // The already-sent account is not listed.
      expect(find.byKey(const ValueKey('adminV2ResendRow_b')), findsNothing);
    });

    testWidgets('the per-row resend button calls the service', (tester) async {
      final called = <String>[];
      await tester.pumpWidget(build(
        records: [rec('a')],
        resendOne: (uid) async {
          called.add(uid);
          return const ResendOutcome(delivered: true, message: 'sent');
        },
      ));
      await tester.tap(find.byKey(const ValueKey('adminV2ResendRow_a')));
      await tester.pumpAndSettle();
      expect(called, ['a']);
    });

    testWidgets('the bulk action confirms then resends the capped batch',
        (tester) async {
      final records = [for (var i = 0; i < 60; i++) rec('u$i')];
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
          find.byKey(const ValueKey('adminV2ResendAllUnverifiedButton')));
      await tester.pumpAndSettle();
      // The confirmation dialog is shown first.
      expect(find.textContaining('Resend to 50 users?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adminV2ConfirmBulkResend')));
      await tester.pumpAndSettle();
      expect(sentUids, isNotNull);
      expect(sentUids!.length, kAdminVerificationResendBatchLimit);
    });

    testWidgets('a non-admin sees the counts but every action is disabled',
        (tester) async {
      await tester.pumpWidget(build(records: [rec('a')], isAdmin: false));
      final bulk = tester.widget<FilledButton>(find.byKey(
          const ValueKey('adminV2ResendAllUnverifiedButton')));
      expect(bulk.onPressed, isNull);
      final row = tester.widget<TextButton>(
          find.byKey(const ValueKey('adminV2ResendRow_a')));
      expect(row.onPressed, isNull);
      expect(find.textContaining('Admin only'), findsOneWidget);
    });
  });
}
