import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/models/admin_operational_metrics.dart';
import 'package:jagspoor/features/admin/services/admin_operational_metrics_service.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';

/// Task 4 — Admin Portal V2 package + booking KPIs.
///
/// Covers the pure aggregation (the numbers a Firestore console spot-check
/// would confirm) AND the real fetch + `farms/{farmId}` province join against a
/// `FakeFirebaseFirestore` — no mocks of the aggregation itself.
void main() {
  final now = DateTime(2026, 11, 13, 15, 30);

  group('AdminPackageRecord', () {
    test('parses the real package doc fields', () {
      final r = AdminPackageRecord.fromMap('p1', {
        'outfitterId': 'o1',
        'title': 'Waterberg Kudu Hunt',
        'farmId': 'f1',
        'status': 'active',
        'quantityAvailable': 3,
        'createdAt': Timestamp.fromDate(now),
      });
      expect(r.id, 'p1');
      expect(r.outfitterId, 'o1');
      expect(r.title, 'Waterberg Kudu Hunt');
      expect(r.farmId, 'f1');
      expect(r.isActive, isTrue);
      expect(r.isSoldOut, isFalse);
      expect(r.isDraftArchived, isFalse);
      expect(r.quantityAvailable, 3);
    });

    test('isSoldOut for sold_out status OR zero/negative quantity', () {
      expect(
          AdminPackageRecord.fromMap('a', {'status': 'sold_out'}).isSoldOut,
          isTrue);
      expect(
          AdminPackageRecord.fromMap('b', {'quantityAvailable': 0}).isSoldOut,
          isTrue);
      expect(
          AdminPackageRecord.fromMap('c', {'quantityAvailable': -2}).isSoldOut,
          isTrue);
      expect(
          AdminPackageRecord.fromMap(
                  'd', {'status': 'active', 'quantityAvailable': 1})
              .isSoldOut,
          isFalse);
    });

    test('isDraftArchived covers draft / archived / deleted', () {
      for (final s in ['draft', 'archived', 'deleted']) {
        expect(AdminPackageRecord.fromMap('x', {'status': s}).isDraftArchived,
            isTrue,
            reason: s);
      }
      expect(AdminPackageRecord.fromMap('x', {'status': 'active'}).isDraftArchived,
          isFalse);
    });

    test('missing farm / province buckets as Unknown Province', () {
      final p = AdminPackageRecord.fromMap('p1', {'status': 'active'});
      expect(p.provinceBucket, kUnknownProvince);
      final resolved = p.withProvince('Limpopo');
      expect(resolved.provinceBucket, 'Limpopo');
    });

    test('a null data map parses without throwing', () {
      final r = AdminPackageRecord.fromMap('p1', null);
      expect(r.status, '');
      expect(r.quantityAvailable, 0);
      expect(r.isActive, isFalse);
    });
  });

  group('AdminPackageMetrics.aggregate', () {
    AdminPackageRecord pkg(
      String id, {
      String status = 'active',
      int qty = 1,
      String province = '',
      String outfitterId = 'o1',
      String title = 'Pkg',
    }) =>
        AdminPackageRecord(
          id: id,
          outfitterId: outfitterId,
          title: title,
          status: status,
          quantityAvailable: qty,
          resolvedProvince: province,
          createdAt: now,
        );

    test('counts total / active / sold-out / draft-archived', () {
      final m = AdminPackageMetrics.aggregate(
        [
          pkg('a'),
          pkg('b', status: 'sold_out'),
          pkg('c', qty: 0), // active status but zero quantity -> sold out
          pkg('d', status: 'draft'),
          pkg('e', status: 'archived'),
          pkg('f', status: 'deleted'),
        ],
        bookingPackageIds: {'a', 'b', 'c', 'd', 'e', 'f'},
        outfitterIds: {'o1'},
        now: now,
      );
      expect(m.totalPackages, 6);
      expect(m.activePackages, 2); // a, c (b carries the sold_out status)
      expect(m.soldOutPackages, 2); // b (status) + c (qty 0)
      expect(m.draftArchivedPackages, 3); // d, e, f
    });

    test('packages per province counts active only + reconciles', () {
      final m = AdminPackageMetrics.aggregate(
        [
          pkg('a', province: 'Limpopo'),
          pkg('b', province: 'Limpopo'),
          pkg('c', province: 'Gauteng'),
          pkg('d'), // no province -> Unknown
          pkg('e', province: 'Limpopo', status: 'draft'), // not active
        ],
        bookingPackageIds: {'a', 'b', 'c', 'd', 'e'},
        outfitterIds: {'o1'},
        now: now,
      );
      final map = m.activeByProvince;
      expect(map['Limpopo'], 2);
      expect(map['Gauteng'], 1);
      expect(map[kUnknownProvince], 1);
      // Every SA province key is present (zero when absent) so it reconciles.
      for (final p in kSaProvinces) {
        expect(map.containsKey(p), isTrue, reason: p);
      }
      // The province breakdown sums to the active total.
      final sum = m.provinceBreakdown.fold<int>(0, (a, e) => a + e.value);
      expect(sum, m.activePackages);
    });

    test('zero-booking packages are ACTIVE packages with no booking', () {
      final m = AdminPackageMetrics.aggregate(
        [
          pkg('booked'),
          pkg('unbooked', title: 'Lonely Package'),
          pkg('draft-unbooked', status: 'draft'), // not active -> excluded
        ],
        bookingPackageIds: {'booked'},
        outfitterIds: {'o1'},
        emailByUid: {'o1': 'outfitter@example.com'},
        now: now,
      );
      expect(m.zeroBookingPackages.length, 1);
      expect(m.zeroBookingPackages.first.id, 'unbooked');
      expect(m.zeroBookingPackages.first.title, 'Lonely Package');
      expect(m.zeroBookingPackages.first.outfitterEmail, 'outfitter@example.com');
      expect(m.zeroBookingPackages.first.daysLive, 0);
    });

    test('outfitters with zero packages', () {
      final m = AdminPackageMetrics.aggregate(
        [pkg('a', outfitterId: 'has-pkg')],
        bookingPackageIds: {'a'},
        outfitterIds: {'has-pkg', 'no-pkg-1', 'no-pkg-2'},
        now: now,
      );
      expect(m.outfittersWithZeroPackages, 2);
    });

    test('a null-title package renders a placeholder title', () {
      final m = AdminPackageMetrics.aggregate(
        [pkg('a', title: '')],
        bookingPackageIds: const {},
        outfitterIds: {'o1'},
        now: now,
      );
      expect(m.zeroBookingPackages.first.title, '(untitled package)');
    });
  });

  group('AdminBookingRecord', () {
    test('normalizes legacy status spellings', () {
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'pending'}).normalizedStatus,
          BookingStatus.pendingApproval);
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'Paid'}).normalizedStatus,
          BookingStatus.confirmed);
    });

    test('isEarned covers Confirmed + Completed only', () {
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'Confirmed'}).isEarned,
          isTrue);
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'Completed'}).isEarned,
          isTrue);
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'Awaiting Payment'})
              .isEarned,
          isFalse);
      expect(
          AdminBookingRecord.fromMap('b', {'status': 'Pending Approval'})
              .isEarned,
          isFalse);
    });

    test('daysToConfirm uses paymentVerifiedAt, never confirmedAt', () {
      final b = AdminBookingRecord.fromMap('b', {
        'status': 'Confirmed',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 5))),
        'paymentVerifiedAt':
            Timestamp.fromDate(now.subtract(const Duration(days: 2))),
        'paymentVerified': true,
        // confirmedAt is deliberately absent (it does not exist).
      });
      expect(b.daysToConfirm, 3);
    });

    test('isStuckPending requires Pending Approval older than the threshold',
        () {
      final stuck = AdminBookingRecord.fromMap('b', {
        'status': 'Pending Approval',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 9))),
      });
      final fresh = AdminBookingRecord.fromMap('b', {
        'status': 'Pending Approval',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
      });
      expect(stuck.isStuckPending(now), isTrue);
      expect(fresh.isStuckPending(now), isFalse);
    });
  });

  group('AdminBookingMetrics.aggregate', () {
    AdminBookingRecord booking(
      String id, {
      String status = 'Pending Approval',
      String hunterId = 'h1',
      String outfitterId = 'o1',
      String packageId = 'p1',
      String packageName = 'Pkg',
      DateTime? createdAt,
      DateTime? paymentVerifiedAt,
      bool paymentVerified = false,
    }) =>
        AdminBookingRecord(
          id: id,
          status: status,
          hunterId: hunterId,
          outfitterId: outfitterId,
          packageId: packageId,
          packageName: packageName,
          createdAt: createdAt ?? now,
          paymentVerifiedAt: paymentVerifiedAt,
          paymentVerified: paymentVerified,
        );

    test('counts by status across all six canonical statuses', () {
      final m = AdminBookingMetrics.aggregate(
        [
          booking('a', status: 'Pending Approval'),
          booking('b', status: 'Awaiting Payment'),
          booking('c', status: 'Confirmed'),
          booking('d', status: 'Completed'),
          booking('e', status: 'Declined'),
          booking('f', status: 'Cancelled'),
        ],
        emailByUid: const {},
        now: now,
      );
      expect(m.totalBookings, 6);
      expect(m.byStatus[BookingStatus.pendingApproval], 1);
      expect(m.byStatus[BookingStatus.approvedAwaitingPayment], 1);
      expect(m.byStatus[BookingStatus.confirmed], 1);
      expect(m.byStatus[BookingStatus.completed], 1);
      expect(m.byStatus[BookingStatus.declined], 1);
      expect(m.byStatus[BookingStatus.cancelled], 1);
    });

    test('conversion = (Confirmed + Completed) / Total, 1 decimal', () {
      final m = AdminBookingMetrics.aggregate(
        [
          booking('a', status: 'Confirmed'),
          booking('b', status: 'Completed'),
          booking('c', status: 'Pending Approval'),
        ],
        emailByUid: const {},
        now: now,
      );
      expect(m.conversionPercent, closeTo(66.7, 0.05));
      expect(m.conversionLabel, '66.7%');
    });

    test('conversion is 0% when there are no bookings', () {
      final m = AdminBookingMetrics.aggregate(const [], emailByUid: const {});
      expect(m.conversionPercent, 0.0);
      expect(m.conversionLabel, '0.0%');
    });

    test('stuck pending list carries emails + package title + days', () {
      final m = AdminBookingMetrics.aggregate(
        [
          booking(
            'stuck-1',
            hunterId: 'h1',
            outfitterId: 'o1',
            packageName: 'Kudu Hunt',
            createdAt: now.subtract(const Duration(days: 10)),
          ),
        ],
        emailByUid: {'h1': 'hunter@example.com', 'o1': 'outfitter@example.com'},
        now: now,
      );
      expect(m.stuckPending.length, 1);
      final row = m.stuckPending.first;
      expect(row.id, 'stuck-1');
      expect(row.hunterEmail, 'hunter@example.com');
      expect(row.outfitterEmail, 'outfitter@example.com');
      expect(row.packageTitle, 'Kudu Hunt');
      expect(row.daysStuck, 10);
    });

    test('top outfitters grouped, sorted DESC, capped at 5', () {
      final bookings = <AdminBookingRecord>[];
      // o1 -> 3 bookings, o2 -> 2, o3 -> 1, o4 -> 1, o5 -> 1, o6 -> 1.
      for (var i = 0; i < 3; i++) {
        bookings.add(booking('o1-$i', outfitterId: 'o1', status: 'Confirmed'));
      }
      for (var i = 0; i < 2; i++) {
        bookings.add(booking('o2-$i', outfitterId: 'o2', status: 'Confirmed'));
      }
      bookings.add(booking('o3-0', outfitterId: 'o3'));
      bookings.add(booking('o4-0', outfitterId: 'o4'));
      bookings.add(booking('o5-0', outfitterId: 'o5'));
      bookings.add(booking('o6-0', outfitterId: 'o6'));

      final m = AdminBookingMetrics.aggregate(
        bookings,
        emailByUid: const {},
        outfitterNameByUid: const {'o1': 'Alpha Safaris', 'o2': 'Beta Hunts'},
        now: now,
      );
      expect(m.topOutfitters.length, 5);
      expect(m.topOutfitters.first.outfitterId, 'o1');
      expect(m.topOutfitters.first.name, 'Alpha Safaris');
      expect(m.topOutfitters.first.total, 3);
      expect(m.topOutfitters.first.confirmed, 3);
      expect(m.topOutfitters.first.conversionLabel, '100.0%');
      expect(m.topOutfitters[1].outfitterId, 'o2');
    });

    test('avg days to confirm uses payment-verified earned bookings only', () {
      final m = AdminBookingMetrics.aggregate(
        [
          booking('a',
              status: 'Confirmed',
              createdAt: now.subtract(const Duration(days: 4)),
              paymentVerifiedAt: now,
              paymentVerified: true),
          booking('b',
              status: 'Completed',
              createdAt: now.subtract(const Duration(days: 8)),
              paymentVerifiedAt: now,
              paymentVerified: true),
          // Earned but paymentVerified flag false -> excluded.
          booking('c',
              status: 'Confirmed',
              createdAt: now.subtract(const Duration(days: 100)),
              paymentVerifiedAt: now),
          // Not earned -> excluded.
          booking('d',
              status: 'Pending Approval',
              createdAt: now.subtract(const Duration(days: 100)),
              paymentVerifiedAt: now,
              paymentVerified: true),
        ],
        emailByUid: const {},
        now: now,
      );
      // (4 + 8) / 2 = 6.0
      expect(m.avgDaysToConfirm, closeTo(6.0, 0.001));
      expect(m.avgDaysLabel, '6.0');
    });

    test('avg days is "—" when no earned booking has paymentVerifiedAt', () {
      final m = AdminBookingMetrics.aggregate(
        [booking('a', status: 'Confirmed')],
        emailByUid: const {},
        now: now,
      );
      expect(m.avgDaysToConfirm, isNull);
      expect(m.avgDaysLabel, '—');
    });
  });

  group('AdminOperationalMetricsService.fetchData (FakeFirestore)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      AdminOperationalMetricsService.firestoreForTesting = firestore;
    });

    tearDown(() {
      AdminOperationalMetricsService.firestoreForTesting = null;
    });

    test('joins farms/{farmId} for the province; missing farm -> Unknown', () async {
      await firestore.collection('farms').doc('f1').set({
        'name': 'Bosveld Ranch',
        'province': 'Limpopo',
      });
      await firestore.collection('packages').doc('p1').set({
        'outfitterId': 'o1',
        'title': 'Kudu Hunt',
        'farmId': 'f1',
        'status': 'active',
        'quantityAvailable': 2,
      });
      // No farmId -> Unknown bucket, package NOT dropped.
      await firestore.collection('packages').doc('p2').set({
        'outfitterId': 'o1',
        'title': 'No Farm',
        'status': 'active',
        'quantityAvailable': 1,
      });
      // farmId points at a missing farm doc -> Unknown bucket.
      await firestore.collection('packages').doc('p3').set({
        'outfitterId': 'o1',
        'title': 'Missing Farm',
        'farmId': 'does-not-exist',
        'status': 'active',
        'quantityAvailable': 1,
      });

      final data = await AdminOperationalMetricsService.instance.fetchData();
      final m = data.packageMetrics(now: now);

      expect(m.totalPackages, 3); // nothing dropped
      expect(m.activePackages, 3);
      expect(m.activeByProvince['Limpopo'], 1);
      expect(m.activeByProvince[kUnknownProvince], 2);
    });

    test('excludes disabled outfitters from the outfitter set', () async {
      await firestore.collection('outfitters').doc('o1').set({
        'email': 'active@example.com',
        'role': 'outfitter',
      });
      await firestore.collection('outfitters').doc('o2').set({
        'email': 'gone@example.com',
        'disabled': true,
      });

      final data = await AdminOperationalMetricsService.instance.fetchData();
      expect(data.outfitterIds.contains('o1'), isTrue);
      expect(data.outfitterIds.contains('o2'), isFalse);
    });

    test('userEmailByUid is reused (no second users read) + outfitter email merged',
        () async {
      await firestore.collection('outfitters').doc('o1').set({
        'email': 'outfitter@example.com',
      });
      await firestore.collection('bookings').doc('b1').set({
        'status': 'Pending Approval',
        'hunterId': 'h1',
        'outfitterId': 'o1',
        'createdAt':
            Timestamp.fromDate(now.subtract(const Duration(days: 10))),
      });

      final data = await AdminOperationalMetricsService.instance.fetchData(
        userEmailByUid: {'h1': 'hunter@example.com'},
      );
      final m = data.bookingMetrics(now: now);

      expect(m.stuckPending.first.hunterEmail, 'hunter@example.com');
      expect(m.stuckPending.first.outfitterEmail, 'outfitter@example.com');
    });

    test('a broken collection degrades gracefully (no throw)', () async {
      // No data seeded — every collection read returns empty, not an error.
      final data = await AdminOperationalMetricsService.instance.fetchData();
      expect(data.packages, isEmpty);
      expect(data.bookings, isEmpty);
      expect(data.packageMetrics(now: now).totalPackages, 0);
      expect(data.bookingMetrics(now: now).totalBookings, 0);
    });
  });
}
