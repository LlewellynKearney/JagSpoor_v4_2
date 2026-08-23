import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/services/push_notification_service.dart';

/// Unit tests for [PushNotificationService] (Task 2): FCM token registration
/// on `users/{uid}`, token removal on sign-out, refresh re-persistence, and
/// the foreground message → local notification mapping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saveTokenForUser', () {
    test('stores the token on users/{uid} via arrayUnion + timestamp', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );

      final saved = await service.saveTokenForUser('uid-1', 'token-abc');

      expect(saved, isTrue);
      final doc = await firestore.collection('users').doc('uid-1').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['fcmTokens'], contains('token-abc'));
      expect(data.containsKey('fcmTokensUpdatedAt'), isTrue);
    });

    test('accumulates multiple device tokens without clobbering', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );

      await service.saveTokenForUser('uid-1', 'token-abc');
      await service.saveTokenForUser('uid-1', 'token-def');

      final doc = await firestore.collection('users').doc('uid-1').get();
      final tokens = doc.data()!['fcmTokens'] as List<dynamic>;
      expect(tokens, containsAll(<String>['token-abc', 'token-def']));
      expect(tokens, hasLength(2));
    });

    test('merges into an existing user document without wiping fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('uid-1').set({
        'email': 'hunter@example.com',
        'role': 'hunter',
      });
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );

      await service.saveTokenForUser('uid-1', 'token-abc');

      final doc = await firestore.collection('users').doc('uid-1').get();
      expect(doc.data()!['email'], 'hunter@example.com');
      expect(doc.data()!['role'], 'hunter');
      expect(doc.data()!['fcmTokens'], contains('token-abc'));
    });

    test('blank uid or token is a no-op', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );

      expect(await service.saveTokenForUser('', 'token-abc'), isFalse);
      expect(await service.saveTokenForUser('uid-1', ''), isFalse);
      expect(await service.saveTokenForUser('uid-1', '   '), isFalse);

      final docs = await firestore.collection('users').get();
      expect(docs.docs, isEmpty);
    });
  });

  group('removeTokenForUser', () {
    test('removes the device token from users/{uid}', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );
      await service.saveTokenForUser('uid-1', 'token-abc');
      await service.saveTokenForUser('uid-1', 'token-def');

      final removed = await service.removeTokenForUser('uid-1', 'token-abc');

      expect(removed, isTrue);
      final doc = await firestore.collection('users').doc('uid-1').get();
      final tokens = doc.data()!['fcmTokens'] as List<dynamic>;
      expect(tokens, isNot(contains('token-abc')));
      expect(tokens, contains('token-def'));
    });

    test('blank uid or token is a no-op', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
      );
      expect(await service.removeTokenForUser('', 'token-abc'), isFalse);
      expect(await service.removeTokenForUser('uid-1', ''), isFalse);
    });
  });

  group('registerCurrentDevice', () {
    test('resolves + persists the token for the signed-in user', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        tokenProvider: () async => 'token-abc',
      );

      final token = await service.registerCurrentDevice();

      expect(token, 'token-abc');
      final doc = await firestore.collection('users').doc('uid-1').get();
      expect(doc.data()!['fcmTokens'], contains('token-abc'));
      await service.dispose();
    });

    test('unauthenticated caller does nothing', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
        tokenProvider: () async => 'token-abc',
      );

      final token = await service.registerCurrentDevice();

      expect(token, isNull);
      final docs = await firestore.collection('users').get();
      expect(docs.docs, isEmpty);
      await service.dispose();
    });

    test('null token does nothing', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        tokenProvider: () async => null,
      );

      final token = await service.registerCurrentDevice();

      expect(token, isNull);
      final docs = await firestore.collection('users').get();
      expect(docs.docs, isEmpty);
      await service.dispose();
    });

    test('a refreshed token is re-persisted for the current user', () async {
      final firestore = FakeFirebaseFirestore();
      final refreshController = StreamController<String>();
      addTearDown(refreshController.close);
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        tokenProvider: () async => 'token-abc',
        tokenRefreshStream: refreshController.stream,
      );

      await service.registerCurrentDevice();
      refreshController.add('token-rotated');
      // Allow the async listener to run.
      await Future<void>.delayed(Duration.zero);

      final doc = await firestore.collection('users').doc('uid-1').get();
      final tokens = doc.data()!['fcmTokens'] as List<dynamic>;
      expect(tokens, containsAll(<String>['token-abc', 'token-rotated']));
      await service.dispose();
    });
  });

  group('unregisterCurrentDevice', () {
    test('removes the device token for the signed-in user', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'uid-1',
        tokenProvider: () async => 'token-abc',
      );
      await service.registerCurrentDevice();

      await service.unregisterCurrentDevice();

      final doc = await firestore.collection('users').doc('uid-1').get();
      final tokens = doc.data()!['fcmTokens'] as List<dynamic>;
      expect(tokens, isEmpty);
      await service.dispose();
    });

    test('unauthenticated caller is a no-op', () async {
      final firestore = FakeFirebaseFirestore();
      final service = PushNotificationService.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => null,
        tokenProvider: () async => 'token-abc',
      );

      await service.unregisterCurrentDevice();

      final docs = await firestore.collection('users').get();
      expect(docs.docs, isEmpty);
      await service.dispose();
    });
  });

  group('describeMessage', () {
    test('prefers the notification payload title + body', () {
      const message = RemoteMessage(
        notification: RemoteNotification(
          title: 'Booking Status Update',
          body: 'Payment confirmed — your booking is confirmed!',
        ),
        data: {'bookingId': 'booking-1', 'type': 'booking'},
      );

      final description = PushNotificationService.describeMessage(message);

      expect(description.title, 'Booking Status Update');
      expect(description.body, contains('Payment confirmed'));
      expect(description.payload, 'booking-1');
    });

    test('falls back to the data payload for data-only messages', () {
      const message = RemoteMessage(
        data: {
          'title': 'Package Status Update',
          'body': "'Kudu Package' is now Sold Out.",
          'packageId': 'pkg-1',
        },
      );

      final description = PushNotificationService.describeMessage(message);

      expect(description.title, 'Package Status Update');
      expect(description.body, contains('Sold Out'));
      expect(description.payload, 'pkg-1');
    });

    test('falls back to the generic title when nothing is provided', () {
      const message = RemoteMessage();

      final description = PushNotificationService.describeMessage(message);

      expect(description.title, 'JagSpoor Notification');
      expect(description.body, '');
      expect(description.payload, isNull);
    });
  });

  group('handleForegroundMessage', () {
    test('routes the mapped title/body/payload to the displayer', () async {
      final displayed = <List<String?>>[];
      final service = PushNotificationService.forTesting(
        notificationDisplayer: (title, body, payload) async {
          displayed.add([title, body, payload]);
        },
      );

      const message = RemoteMessage(
        notification: RemoteNotification(
          title: 'New Booking Request',
          body: 'A hunter just booked Bosveld Kudu Package.',
        ),
        data: {'bookingId': 'booking-1', 'type': 'booking_new'},
      );
      await service.handleForegroundMessage(message);

      expect(displayed, hasLength(1));
      expect(displayed.single[0], 'New Booking Request');
      expect(displayed.single[1], contains('Bosveld Kudu Package'));
      expect(displayed.single[2], 'booking-1');
    });

    test('a displayer failure is swallowed (never throws)', () async {
      final service = PushNotificationService.forTesting(
        notificationDisplayer: (title, body, payload) async {
          throw StateError('display failed');
        },
      );

      const message = RemoteMessage(
        notification: RemoteNotification(title: 'T', body: 'B'),
      );

      await expectLater(service.handleForegroundMessage(message), completes);
    });
  });
}
