import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the push-notification Cloud Functions
/// (Task 2). The Firebase emulator cannot run in this sandbox (no JVM), so
/// these tests encode the trigger contract by parsing
/// `functions/src/index.ts` — mirroring the project's established structural
/// test pattern.
void main() {
  final source = File('functions/src/index.ts').readAsStringSync();

  group('booking triggers', () {
    test('onBookingCreated notifies the outfitter on a new booking', () {
      expect(source, contains('export const onBookingCreated'));
      expect(
        source,
        contains('onDocumentCreated(\n  { document: "bookings/{bookingId}"'),
      );
      expect(source, contains('"New Booking Request"'));
      expect(source, contains('type: "booking_new"'));
    });

    test('onBookingUpdated notifies on status transitions', () {
      expect(source, contains('export const onBookingUpdated'));
      expect(
        source,
        contains('onDocumentUpdated(\n  { document: "bookings/{bookingId}"'),
      );
      expect(source, contains('"Booking Status Update"'));
      // The recipient is the "other" party: hunter actor → outfitter.
      expect(source, contains('actorId && actorId === hunterId'));
    });

    test('onBookingUpdated alerts the outfitter on date-change requests', () {
      expect(source, contains('dateChangeRequestPending'));
      expect(source, contains('"Date Change Requested"'));
      expect(source, contains('type: "date_change"'));
    });

    test('bookingStatusBody covers the off-platform lifecycle statuses', () {
      for (final status in [
        '"pending approval"',
        '"awaiting payment"',
        '"confirmed"',
        '"declined"',
        '"cancelled"',
        '"completed"',
      ]) {
        expect(source, contains('case $status:'), reason: 'missing $status');
      }
    });
  });

  group('package trigger', () {
    test('onPackageUpdated notifies the outfitter on status changes', () {
      expect(source, contains('export const onPackageUpdated'));
      expect(
        source,
        contains('onDocumentUpdated(\n  { document: "packages/{packageId}"'),
      );
      expect(source, contains('"Package Status Update"'));
      expect(source, contains('"Sold Out"'));
      expect(source, contains('type: "package"'));
    });
  });

  group('delivery contract', () {
    test('notifications are dispatched as high-priority FCM multicasts', () {
      expect(source, contains('sendEachForMulticast'));
      expect(source, contains('android: { priority: "high" }'));
    });

    test('tokens are read from users/{uid}.fcmTokens', () {
      expect(source, contains('extractFcmTokens'));
      expect(source, contains('.fcmTokens'));
      expect(
        source,
        contains('firestore().collection("users").doc(userId).get()'),
      );
    });

    test('every push carries a title, body, and data payload', () {
      // sendFcm is the single dispatch funnel with a fixed signature.
      expect(
        source,
        contains(
          'async function sendFcm(\n  tokens: string[],\n  title: string,\n'
          '  body: string,\n  data: Record<string, string>\n)',
        ),
      );
      expect(source, contains('notification: { title, body }'));
      expect(source, contains('data,'));
    });
  });
}
