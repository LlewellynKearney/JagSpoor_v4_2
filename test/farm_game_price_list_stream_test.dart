import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_game_price_entry.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_date_formatter.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_game_price_list_manager.dart';

/// Unit tests for the Custom Package Builder's farm price-list stream contract.
///
/// Locks in the Task-2 "fix the blank screen" changes:
///  1. The species stream no longer uses a server-side `.orderBy('speciesName')`
///     (an equality + orderBy combo that required a composite index which, when
///     missing, errored / hung the `StreamBuilder` -> blank builder screen).
///     Instead the entries are sorted client-side by species name.
///  2. The stream is wrapped in `OfflineStreamGuard.offlineResilient` so a hard
///     error (permissions / offline) emits the fallback `[]` and completes
///     instead of hanging the consumer.
void main() {
  // Construct a FakeFirebaseFirestore FIRST so the mock `FieldValuePlatform`
  // binds before any `FieldValue.serverTimestamp()` is realised (mirrors the
  // `optic_log_service_test` isolation pattern).
  FakeFirebaseFirestore();

  FarmGamePriceListManager _service(String? uid) =>
      FarmGamePriceListManager.forTesting(
        firestore: FakeFirebaseFirestore(),
        currentUserIdResolver: () => uid,
      );

  Future<void> _seedSpecies(
    FirebaseFirestore fake, {
    required String farmId,
    required String outfitterId,
    required String speciesName,
    double price = 1000,
    int qty = 5,
  }) async {
    await fake.collection('farm_pricelists').add({
      'farmId': farmId,
      'outfitterId': outfitterId,
      'speciesName': speciesName,
      'quantity': qty,
      'priceZAR': price,
      'gender': 'Any',
      'hornTuskLength': '',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  group('getFarmPriceListStreamForHunter (client-side sort + resilient guard)',
      () {
    test('null uid -> empty stream (no throw, no Firestore access)', () async {
      final service = _service(null);
      // An unauthenticated caller: the stream short-circuits to Stream.empty()
      // (no Firestore access, no [core/no-app]). Stream.empty() completes
      // without emitting, so `toList` yields `[]` -- the consuming
      // StreamBuilder lands in the empty-state branch, never a hung spinner.
      final entries =
          await service.getFarmPriceListStreamForHunter('farm-1').toList();
      expect(entries, const <FarmGamePriceEntry>[]);
    });

    test('returns the farm\'s species sorted by name (client-side, no server orderBy)',
        () async {
      final fake = FakeFirebaseFirestore();
      final service = FarmGamePriceListManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'hunter-1',
      );
      // Seed in NON-alphabetical insertion order to prove the client-side
      // sort (not the snapshot order) drives the output ordering.
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Kudu');
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Impala');
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Eland');

      final entries =
          await service.getFarmPriceListStreamForHunter('farm-1').first;

      expect(entries.map((e) => e.speciesName).toList(),
          ['Eland', 'Impala', 'Kudu']);
    });

    test('only the requested farm\'s species are returned (farmId filter)', () async {
      final fake = FakeFirebaseFirestore();
      final service = FarmGamePriceListManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'hunter-1',
      );
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Kudu');
      await _seedSpecies(fake,
          farmId: 'farm-2', outfitterId: 'o1', speciesName: 'Impala');

      final entries =
          await service.getFarmPriceListStreamForHunter('farm-1').first;

      expect(entries, hasLength(1));
      expect(entries.single.speciesName, 'Kudu');
    });

    test('getFarmPriceListForHunter (one-shot) sorts client-side too', () async {
      final fake = FakeFirebaseFirestore();
      final service = FarmGamePriceListManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'hunter-1',
      );
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Warthog');
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Blesbok');

      final entries = await service.getFarmPriceListForHunter('farm-1');

      expect(entries.map((e) => e.speciesName).toList(),
          ['Blesbok', 'Warthog']);
    });
  });

  group('getFarmPriceListStream (owner-scoped, client-side sort)', () {
    test('only the owner\'s entries are returned (outfitterId filter)', () async {
      final fake = FakeFirebaseFirestore();
      final service = FarmGamePriceListManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'o1',
      );
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Kudu');
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o2', speciesName: 'Impala');

      final entries = await service.getFarmPriceListStream('farm-1').first;

      expect(entries, hasLength(1));
      expect(entries.single.speciesName, 'Kudu');
      expect(entries.single.outfitterId, 'o1');
    });

    test('client-side sort applies to the owner-scoped stream too', () async {
      final fake = FakeFirebaseFirestore();
      final service = FarmGamePriceListManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'o1',
      );
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Zebra');
      await _seedSpecies(fake,
          farmId: 'farm-1', outfitterId: 'o1', speciesName: 'Aardvark');

      final entries = await service.getFarmPriceListStream('farm-1').first;

      expect(entries.map((e) => e.speciesName).toList(),
          ['Aardvark', 'Zebra']);
    });
  });

  group('submitCustomPackageBooking (hunter-mode booking write)', () {
    FarmGamePriceListManager bookingService({
      required String? uid,
      required FirebaseFirestore firestore,
    }) {
      return FarmGamePriceListManager.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => uid,
      );
    }

    test('writes the booking doc to `bookings` with the hunter-mode shape',
        () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'farm-1',
        farmName: 'Test Farm',
        outfitterId: 'outfitter-1',
        pricelistId: 'farm_pricelists:farm-1',
        selectedItems: [
          {
            'name': 'Kudu',
            'quantity': 2,
            'unitPriceHunterZAR': 5000.0,
            'lineTotal': 10000.0,
            'outfitterBasePrice': 5000.0,
            'hunterDisplayPriceZAR': 5000.0,
          },
        ],
        lodgingCatering: [
          {
            'name': 'Accommodation',
            'quantity': 3,
            'unitPriceHunterZAR': 800.0,
            'lineTotal': 2400.0,
            'outfitterBasePrice': 800.0,
            'hunterDisplayPriceZAR': 800.0,
          },
        ],
        combinedTotalZAR: 12400.0,
        checkInDate: '2026-09-01',
        checkOutDate: '2026-09-04',
        huntingDays: 3,
        hunterCount: 2,
        observerCount: 1,
      );

      // The returned id matches the doc written to the `bookings` collection.
      final snap = await fake.collection('bookings').doc(bookingId).get();
      expect(snap.exists, isTrue);

      final data = snap.data()!;
      // Hunter-mode contract: pending approval, custom-package flag, hunter id.
      expect(data['status'], BookingStatus.pendingApproval);
      expect(data['isCustomPackage'], isTrue);
      expect(data['hunterId'], 'hunter-1');
      expect(data['outfitterId'], 'outfitter-1');
      expect(data['farmId'], 'farm-1');
      expect(data['farmName'], 'Test Farm');
      expect(data['packageId'], 'CUSTOM_BUILT');
      // No platform commission: base == total.
      expect(data['basePriceRands'], 12400.0);
      expect(data['totalHunterPriceRands'], 12400.0);
      // Party + window meta flow through to the booking doc.
      expect(data['hunterCount'], 2);
      expect(data['observerCount'], 1);
      expect(data['huntingDays'], 3);
      expect(data['checkInDate'], '2026-09-01');
      expect(data['checkOutDate'], '2026-09-04');
      // Dual-key guarantee: the custom-package booking writes the hunt window
      // under ALL alias families so any downstream consumer (calendar
      // resolver, UI card) finds a value regardless of which key it reads.
      expect(data['startDate'], '2026-09-01');
      expect(data['endDate'], '2026-09-04');
      expect(data['availabilityStart'], '2026-09-01');
      expect(data['availabilityEnd'], '2026-09-04');
      // Both line-item lists are persisted (normalized to the dashboard shape).
      expect((data['selectedItemsList'] as List).length, 1);
      expect((data['lodgingCateringList'] as List).length, 1);
      final speciesLine =
          (data['selectedItemsList'] as List).first as Map<String, dynamic>;
      expect(speciesLine['name'], 'Kudu');
      expect(speciesLine['quantity'], 2);
      expect(speciesLine['hunterPrice'], 5000.0);
    });

    test('rejects an unauthenticated caller', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: null, firestore: fake);

      expect(
        () => service.submitCustomPackageBooking(
          farmId: 'farm-1',
          outfitterId: 'outfitter-1',
          selectedItems: [
            {'name': 'Kudu', 'quantity': 1, 'unitPriceHunterZAR': 100.0}
          ],
          combinedTotalZAR: 100.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('prevents an outfitter from booking their own farm', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'outfitter-1', firestore: fake);

      expect(
        () => service.submitCustomPackageBooking(
          farmId: 'farm-1',
          outfitterId: 'outfitter-1',
          selectedItems: [
            {'name': 'Kudu', 'quantity': 1, 'unitPriceHunterZAR': 100.0}
          ],
          combinedTotalZAR: 100.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects an empty selection', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      expect(
        () => service.submitCustomPackageBooking(
          farmId: 'farm-1',
          outfitterId: 'outfitter-1',
          selectedItems: const [],
          lodgingCatering: const [],
          combinedTotalZAR: 100.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a non-positive total', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      expect(
        () => service.submitCustomPackageBooking(
          farmId: 'farm-1',
          outfitterId: 'outfitter-1',
          selectedItems: [
            {'name': 'Kudu', 'quantity': 1, 'unitPriceHunterZAR': 100.0}
          ],
          combinedTotalZAR: 0.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('resolves district + province from farms/{farmId} so the calendar '
        'event carries a located title + location', () async {
      final fake = FakeFirebaseFirestore();
      // Seed the farm doc the booking resolves the region from.
      await fake.collection('farms').doc('farm-1').set({
        'name': 'Bosveld Ranch',
        'district': 'Waterberg',
        'province': 'Limpopo',
      });
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'farm-1',
        farmName: 'Bosveld Ranch',
        outfitterId: 'outfitter-1',
        selectedItems: [
          {'name': 'Kudu', 'quantity': 1, 'unitPriceHunterZAR': 5000.0}
        ],
        combinedTotalZAR: 5000.0,
      );

      final data =
          (await fake.collection('bookings').doc(bookingId).get()).data()!;
      expect(data['farmName'], 'Bosveld Ranch');
      expect(data['district'], 'Waterberg');
      expect(data['province'], 'Limpopo');
      // The packageName carries the farm name; the booking doc's region
      // fields let the outfitter card render a located booking without a
      // separate farm read.
      expect(data['packageName'], contains('Bosveld Ranch'));
    });

    test('backfills farmName + packageName from farms/{farmId} when the '
        'caller omits farmName', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('farms').doc('farm-9').set({
        'name': 'Springbok Plains',
        'district': 'Central Karoo',
        'province': 'Northern Cape',
      });
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'farm-9',
        outfitterId: 'outfitter-1',
        selectedItems: [
          {'name': 'Springbok', 'quantity': 1, 'unitPriceHunterZAR': 1200.0}
        ],
        combinedTotalZAR: 1200.0,
      );

      final data =
          (await fake.collection('bookings').doc(bookingId).get()).data()!;
      expect(data['farmName'], 'Springbok Plains');
      expect(data['packageName'], 'Custom Package - Springbok Plains');
      expect(data['district'], 'Central Karoo');
      expect(data['province'], 'Northern Cape');
    });

    test('omits region fields gracefully when the farm doc is missing '
        '(no crash, calendar falls back to farm name only)', () async {
      final fake = FakeFirebaseFirestore();
      // No farms doc seeded.
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'ghost-farm',
        farmName: 'Ghost Farm',
        outfitterId: 'outfitter-1',
        selectedItems: [
          {'name': 'Impala', 'quantity': 1, 'unitPriceHunterZAR': 900.0}
        ],
        combinedTotalZAR: 900.0,
      );

      final data =
          (await fake.collection('bookings').doc(bookingId).get()).data()!;
      expect(data['farmName'], 'Ghost Farm');
      expect(data.containsKey('district'), isFalse);
      expect(data.containsKey('province'), isFalse);
    });

    test('passes the builder\'s gender / horn / limit / fee-unit spec fields '
        'through to the booking (normalizeItem passthrough)', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'farm-1',
        farmName: 'Test Farm',
        outfitterId: 'outfitter-1',
        selectedItems: [
          {
            'name': 'Kudu',
            'displayLabel': 'Kudu',
            'speciesName': 'Kudu',
            'sex': 'Male',
            'sexLabel': 'Male',
            'trophySizeRange': '>50"',
            'hornTuskLength': '52"',
            'hornTuskUnit': 'inches',
            'itemType': 'species',
            'feeType': null,
            'quantityLimit': 3,
            'quantity': 2,
            'unitPriceHunterZAR': 5000.0,
            'lineTotal': 10000.0,
            'outfitterBasePrice': 5000.0,
            'hunterDisplayPriceZAR': 5000.0,
          },
        ],
        lodgingCatering: [
          {
            'name': 'Overnight Accommodation (Hunter)',
            'displayLabel': 'Overnight Accommodation (Hunter)',
            'itemType': 'fee',
            'feeType': 'overnight_accommodation_hunter',
            'feeUnitLabel': 'Per night',
            'quantityNoun': 'nights',
            'quantity': 3,
            'unitPriceHunterZAR': 800.0,
            'lineTotal': 2400.0,
            'outfitterBasePrice': 800.0,
            'hunterDisplayPriceZAR': 800.0,
          },
        ],
        combinedTotalZAR: 12400.0,
      );

      final data =
          (await fake.collection('bookings').doc(bookingId).get()).data()!;

      // Species line: gender / horn / limit specs survive the normalization.
      final speciesLine =
          (data['selectedItemsList'] as List).first as Map<String, dynamic>;
      expect(speciesLine['sex'], 'Male');
      expect(speciesLine['sexLabel'], 'Male');
      expect(speciesLine['trophySizeRange'], '>50"');
      expect(speciesLine['hornTuskLength'], '52"');
      expect(speciesLine['hornTuskUnit'], 'inches');
      expect(speciesLine['quantityLimit'], 3);
      expect(speciesLine['itemType'], 'species');
      expect(speciesLine['feeType'], isNull);

      // Fee line: the per-category unit semantics survive the normalization.
      final feeLine = (data['lodgingCateringList'] as List).first
          as Map<String, dynamic>;
      expect(feeLine['itemType'], 'fee');
      expect(feeLine['feeType'], 'overnight_accommodation_hunter');
      expect(feeLine['feeUnitLabel'], 'Per night');
      expect(feeLine['quantityNoun'], 'nights');
      expect(feeLine['quantity'], 3);
      expect(feeLine['hunterPrice'], 800.0);
    });

    test(
        'dual-key sync: the date resolver (resolveWindow) reads the hunt '
        'window from a custom-package booking regardless of which alias a '
        'consumer reads', () async {
      final fake = FakeFirebaseFirestore();
      final service = bookingService(uid: 'hunter-1', firestore: fake);

      final bookingId = await service.submitCustomPackageBooking(
        farmId: 'farm-1',
        farmName: 'Test Farm',
        outfitterId: 'outfitter-1',
        selectedItems: [
          {'name': 'Kudu', 'quantity': 1, 'unitPriceHunterZAR': 5000.0},
        ],
        combinedTotalZAR: 5000.0,
        checkInDate: '2026-09-01',
        checkOutDate: '2026-09-04',
        huntingDays: 3,
        hunterCount: 1,
      );

      final data =
          (await fake.collection('bookings').doc(bookingId).get()).data()!;

      // All alias families are populated on the booking doc.
      expect(data['checkInDate'], '2026-09-01');
      expect(data['startDate'], '2026-09-01');
      expect(data['availabilityStart'], '2026-09-01');
      expect(data['checkOutDate'], '2026-09-04');
      expect(data['endDate'], '2026-09-04');
      expect(data['availabilityEnd'], '2026-09-04');

      // The SAME resolver the UI card uses resolves the
      // window from the booking's dual-key payload.
      final window =
          BookingDateFormatter.resolveWindow(data);
      expect(window, isNotNull);
      expect(window!.start, DateTime(2026, 9, 1));
      // resolveWindow normalizes end to the day AFTER the final hunt day.
      expect(window.end, DateTime(2026, 9, 5));
    });
  });
}
