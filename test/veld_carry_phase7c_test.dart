import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_map_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_species_availability_screen.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 7C contract tests — camp map (outfitter-only) + species availability
/// (hunter).
///
/// No real Firebase: the map projection and the species aggregation are pure
/// functions, and the repository reads run against `FakeFirebaseFirestore`
/// through the repository's `forTesting` seam.
void main() {
  const outfitterUid = 'outfitter-1';
  const hunterUid = 'hunter-1';
  const farmId = 'farm-1';

  final theme = ThemeController();

  Camp camp({
    required String id,
    String name = 'North Camp',
    double? lat,
    double? lng,
  }) =>
      Camp(
        id: id,
        farmId: farmId,
        name: name,
        totalSizeHa: 1000,
        province: 'Limpopo',
        district: 'Waterberg',
        lat: lat,
        lng: lng,
        veldType: 'Mixed bushveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 10,
      );

  StockEntry stock({
    required String campId,
    required String speciesName,
    required int count,
    String? scientificName,
    bool? isCounted,
  }) =>
      StockEntry(
        id: '$campId-${speciesName.toLowerCase()}',
        campId: campId,
        speciesName: speciesName,
        scientificName: scientificName,
        count: count,
        avgWeightKg: 200,
        lsuPerAnimal: 1.0,
        guPerAnimal: 0.5,
        buPerAnimal: 0.5,
        isCounted: isCounted,
      );

  /// Hunter-side repository — no uid resolver, so an ownership check would
  /// throw. The hunter reads must never need one.
  VeldCarryRepository hunterRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(firestore: firestore);

  Future<void> seedCamp(
    FakeFirebaseFirestore firestore,
    Camp value, {
    List<String>? allowedHunterUids,
  }) async {
    final data = Map<String, dynamic>.from(value.toMap());
    if (allowedHunterUids != null) {
      data[Camp.allowedHunterUidsField] = allowedHunterUids;
    }
    await firestore
        .collection('users')
        .doc(outfitterUid)
        .collection('farms')
        .doc(farmId)
        .collection('veldCamps')
        .doc(value.id)
        .set(data);
  }

  Future<void> seedStock(
    FakeFirebaseFirestore firestore,
    String campId,
    StockEntry entry,
  ) async {
    await firestore
        .collection('users')
        .doc(outfitterUid)
        .collection('farms')
        .doc(farmId)
        .collection('veldCamps')
        .doc(campId)
        .collection('stock')
        .doc(entry.id)
        .set(entry.toMap());
  }

  Future<void> seedBooking(
    FakeFirebaseFirestore firestore, {
    String status = BookingStatus.confirmed,
  }) async {
    await firestore.collection('bookings').doc('booking-1').set({
      'hunterId': hunterUid,
      'outfitterUid': outfitterUid,
      'outfitterId': outfitterUid,
      'farmId': farmId,
      'status': status,
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // 1. Camp map — pure relative-position projection
  // ══════════════════════════════════════════════════════════════════════
  group('camp map relative positions', () {
    test('the south-west camp lands in one corner and the north-east camp in '
        'the opposite corner', () {
      final southWest = camp(id: 'sw', lat: -24.5, lng: 27.5);
      final northEast = camp(id: 'ne', lat: -23.5, lng: 28.5);
      final bounds =
          VeldCampMapLayout.boundsOf([southWest, northEast])!;

      final sw = VeldCampMapLayout.relativePosition(southWest, bounds);
      final ne = VeldCampMapLayout.relativePosition(northEast, bounds);

      // Min lat / min lng -> bottom-left of a screen (y grows downward).
      expect(sw.x, 0.0);
      expect(sw.y, 1.0);
      // Max lat / max lng -> the opposite (top-right) corner.
      expect(ne.x, 1.0);
      expect(ne.y, 0.0);

      // Opposite corners: the pair sums to 1 on both axes.
      expect(sw.x + ne.x, 1.0);
      expect(sw.y + ne.y, 1.0);
    });

    test('a camp in the middle of the farm sits at the centre', () {
      final southWest = camp(id: 'sw', lat: -24.0, lng: 27.0);
      final northEast = camp(id: 'ne', lat: -23.0, lng: 29.0);
      final middle = camp(id: 'mid', lat: -23.5, lng: 28.0);
      final bounds =
          VeldCampMapLayout.boundsOf([southWest, northEast, middle])!;

      final position = VeldCampMapLayout.relativePosition(middle, bounds);
      expect(position.x, closeTo(0.5, 1e-9));
      expect(position.y, closeTo(0.5, 1e-9));
    });

    test('a single located camp collapses to the centre instead of dividing '
        'by zero', () {
      final only = camp(id: 'only', lat: -24.0, lng: 28.0);
      final bounds = VeldCampMapLayout.boundsOf([only])!;

      final position = VeldCampMapLayout.relativePosition(only, bounds);
      expect(position.x, 0.5);
      expect(position.y, 0.5);
      expect(VeldCampMapLayout.zoomFor(bounds), 14);
    });

    test('camps without a location are excluded from the map and listed '
        'separately', () {
      final located = camp(id: 'located', lat: -24.0, lng: 28.0);
      final noLat = camp(id: 'no-lat', lng: 28.2);
      final noLng = camp(id: 'no-lng', lat: -24.4);
      final noBoth = camp(id: 'no-both');
      final all = [located, noLat, noLng, noBoth];

      expect(
        VeldCampMapLayout.campsWithLocation(all).map((c) => c.id),
        ['located'],
      );
      expect(
        VeldCampMapLayout.campsWithoutLocation(all).map((c) => c.id),
        ['no-lat', 'no-lng', 'no-both'],
      );

      // Bounds only ever consider the located camp.
      final bounds = VeldCampMapLayout.boundsOf(all)!;
      expect(bounds.minLat, -24.0);
      expect(bounds.maxLat, -24.0);
      expect(bounds.centreLng, 28.0);
    });

    test('boundsOf is null when no camp has a location', () {
      expect(
        VeldCampMapLayout.boundsOf([camp(id: 'a'), camp(id: 'b')]),
        isNull,
      );
      expect(VeldCampMapLayout.boundsOf(const <Camp>[]), isNull);
    });

    test('the initial zoom tightens as the farm spread shrinks', () {
      VeldCampMapBounds boundsWith(double span) => VeldCampMapBounds(
            minLat: -24 - span,
            maxLat: -24 + span,
            minLng: 28 - span,
            maxLng: 28 + span,
          );

      final wide = VeldCampMapLayout.zoomFor(boundsWith(3));
      final medium = VeldCampMapLayout.zoomFor(boundsWith(0.5));
      final tight = VeldCampMapLayout.zoomFor(boundsWith(0.02));

      expect(tight, greaterThan(medium));
      expect(medium, greaterThan(wide));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2. Species aggregation
  // ══════════════════════════════════════════════════════════════════════
  group('species availability aggregation', () {
    test('sums the same species across camps and lists every camp', () {
      final result = VeldCarryRepository.aggregateSpeciesAvailability({
        'North Camp': [
          stock(campId: 'north', speciesName: 'Greater Kudu', count: 4),
        ],
        'South Camp': [
          stock(campId: 'south', speciesName: 'Greater Kudu', count: 6),
        ],
      });

      expect(result, hasLength(1));
      expect(result.single.speciesName, 'Greater Kudu');
      expect(result.single.totalCount, 10);
      expect(result.single.campNames, ['North Camp', 'South Camp']);
      expect(
        result.single.availableOnLabel,
        'Available on: North Camp, South Camp',
      );
    });

    test('excludes present-only species (baboon, vervet, porcupine, aardvark)',
        () {
      final result = VeldCarryRepository.aggregateSpeciesAvailability({
        'North Camp': [
          stock(campId: 'north', speciesName: 'Greater Kudu', count: 3),
          stock(campId: 'north', speciesName: 'Chacma Baboon', count: 12),
          stock(campId: 'north', speciesName: 'Vervet Monkey', count: 7),
          stock(campId: 'north', speciesName: 'Cape Porcupine', count: 2),
          stock(campId: 'north', speciesName: 'Aardvark', count: 1),
        ],
      });

      expect(result.map((s) => s.speciesName), ['Greater Kudu']);
      expect(
        result.any((s) => s.speciesName.toLowerCase().contains('baboon')),
        isFalse,
      );
    });

    test('excludes species with a zero count', () {
      final result = VeldCarryRepository.aggregateSpeciesAvailability({
        'North Camp': [
          stock(campId: 'north', speciesName: 'Greater Kudu', count: 0),
          stock(campId: 'north', speciesName: 'Impala', count: 5),
        ],
      });

      expect(result.map((s) => s.speciesName), ['Impala']);
    });

    test('orders the most abundant species first', () {
      final result = VeldCarryRepository.aggregateSpeciesAvailability({
        'North Camp': [
          stock(campId: 'north', speciesName: 'Impala', count: 2),
          stock(campId: 'north', speciesName: 'Greater Kudu', count: 9),
          stock(campId: 'north', speciesName: 'Blesbok', count: 5),
        ],
      });

      expect(
        result.map((s) => s.speciesName),
        ['Greater Kudu', 'Blesbok', 'Impala'],
      );
    });

    test('resolves the scientific name from the species table', () {
      final result = VeldCarryRepository.aggregateSpeciesAvailability({
        'North Camp': [
          stock(campId: 'north', speciesName: 'Greater Kudu', count: 3),
        ],
      });

      expect(result.single.scientificName, 'Tragelaphus strepsiceros');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 3. Availability badges
  // ══════════════════════════════════════════════════════════════════════
  group('availability badges', () {
    test('0 / 1 / 9 / 10 map to the documented bands', () {
      expect(speciesAvailabilityBadge(0).label, 'Not available');
      expect(speciesAvailabilityBadge(1).label, 'Limited availability');
      expect(speciesAvailabilityBadge(9).label, 'Limited availability');
      expect(speciesAvailabilityBadge(10).label, 'Good availability');
      expect(speciesAvailabilityBadge(42).label, 'Good availability');
    });

    test('the 1..9 band and the 10+ band use different colours', () {
      expect(
        speciesAvailabilityBadge(1).color,
        isNot(speciesAvailabilityBadge(10).color),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 4. Repository reads + the booking gate
  // ══════════════════════════════════════════════════════════════════════
  group('getSpeciesAvailabilityForHunter', () {
    test('aggregates the farm stock for a signed-in hunter with a booking',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Phase 7D: a hunter camp read is allow-list constrained.
      await seedCamp(
        firestore,
        camp(id: 'north', name: 'North Camp'),
        allowedHunterUids: const [hunterUid],
      );
      await seedCamp(
        firestore,
        camp(id: 'south', name: 'South Camp'),
        allowedHunterUids: const [hunterUid],
      );
      await seedStock(
        firestore,
        'north',
        stock(campId: 'north', speciesName: 'Greater Kudu', count: 4),
      );
      await seedStock(
        firestore,
        'south',
        stock(campId: 'south', speciesName: 'Greater Kudu', count: 6),
      );
      await seedStock(
        firestore,
        'south',
        stock(campId: 'south', speciesName: 'Impala', count: 12),
      );
      await seedStock(
        firestore,
        'north',
        stock(campId: 'north', speciesName: 'Chacma Baboon', count: 9),
      );
      await seedBooking(firestore);

      final result = await hunterRepo(firestore).getSpeciesAvailabilityForHunter(
        farmId,
        hunterUid,
        outfitterUid: outfitterUid,
      );

      expect(result.map((s) => s.speciesName), ['Impala', 'Greater Kudu']);
      final kudu = result.firstWhere((s) => s.speciesName == 'Greater Kudu');
      expect(kudu.totalCount, 10);
      expect(kudu.campNames, ['North Camp', 'South Camp']);
      // The present-only baboon never reaches the hunter.
      expect(result.any((s) => s.speciesName == 'Baboon'), isFalse);
    });

    test('a hunter with NO booking on the farm gets an empty list (fail '
        'closed)', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp(id: 'north', name: 'North Camp'));
      await seedStock(
        firestore,
        'north',
        stock(campId: 'north', speciesName: 'Greater Kudu', count: 8),
      );
      // A booking on a DIFFERENT farm must not unlock this one.
      await firestore.collection('bookings').doc('other').set({
        'hunterId': hunterUid,
        'outfitterId': outfitterUid,
        'farmId': 'some-other-farm',
        'status': BookingStatus.confirmed,
      });

      final result = await hunterRepo(firestore).getSpeciesAvailabilityForHunter(
        farmId,
        hunterUid,
        outfitterUid: outfitterUid,
      );

      expect(result, isEmpty);
    });

    test('a pending (unconfirmed) booking does not unlock the species list',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp(id: 'north', name: 'North Camp'));
      await seedStock(
        firestore,
        'north',
        stock(campId: 'north', speciesName: 'Greater Kudu', count: 8),
      );
      await seedBooking(firestore, status: BookingStatus.pendingApproval);

      final result = await hunterRepo(firestore).getSpeciesAvailabilityForHunter(
        farmId,
        hunterUid,
        outfitterUid: outfitterUid,
      );

      expect(result, isEmpty);
    });

    test('a blank hunter uid fails closed (no unconstrained camp query)',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(
        firestore,
        camp(id: 'north', name: 'North Camp'),
        allowedHunterUids: const [hunterUid],
      );
      await seedStock(
        firestore,
        'north',
        stock(campId: 'north', speciesName: 'Blesbok', count: 3),
      );

      final result = await hunterRepo(firestore).getSpeciesAvailabilityForHunter(
        farmId,
        null,
        outfitterUid: outfitterUid,
      );

      // Phase 7D: the camp read is allow-list constrained, so a missing uid
      // can never be served — and must never fall back to an unconstrained
      // read of the whole farm.
      expect(result, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 5. Hunter privacy — no GPS, no weights
  // ══════════════════════════════════════════════════════════════════════
  group('hunter privacy', () {
    testWidgets('the species screen renders names, counts and camps — never a '
        'weight or a coordinate', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final firestore = FakeFirebaseFirestore();
      await seedCamp(
        firestore,
        camp(id: 'north', name: 'North Camp', lat: -24.123, lng: 28.654),
        allowedHunterUids: const [hunterUid],
      );
      await seedStock(
        firestore,
        'north',
        stock(
          campId: 'north',
          speciesName: 'Greater Kudu',
          count: 11,
          scientificName: 'Tragelaphus strepsiceros',
        ),
      );
      await seedBooking(firestore);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: VeldCarrySpeciesAvailabilityScreen(
            outfitterUid: outfitterUid,
            farmId: farmId,
            farmName: 'Bosveld Ranch',
            theme: theme,
            repository: hunterRepo(firestore),
            currentUidOverride: hunterUid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hunter-safe facts.
      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(find.text('Tragelaphus strepsiceros'), findsOneWidget);
      expect(find.text('11 counted'), findsOneWidget);
      expect(find.text('Available on: North Camp'), findsOneWidget);
      expect(find.text('Good availability'), findsOneWidget);

      // Never a coordinate, a weight, a GU/BU split or a camp size.
      expect(find.textContaining('-24.1'), findsNothing);
      expect(find.textContaining('28.65'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('GU'), findsNothing);
      expect(find.textContaining('BU'), findsNothing);
      // Camp sizes render as "1000 ha" — the space keeps this from matching
      // the word "shared" in the privacy note.
      expect(find.textContaining(' ha'), findsNothing);
      expect(find.textContaining('LSU'), findsNothing);
    });

    test('the hunter-facing sources never reference coordinates or weights',
        () {
      final speciesSource =
          File('lib/features/veld_carry/ui/veld_carry_species_availability_screen.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');
      final hunterViewSource =
          File('lib/features/veld_carry/ui/veld_carry_hunter_view_screen.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');

      for (final source in [speciesSource, hunterViewSource]) {
        // No coordinate access, no weight / GU / BU reads. (Camp SIZE is
        // deliberately shared with hunters by the Phase 4 contract, so
        // `totalSizeHa` is only forbidden on the species screen below.)
        expect(source.contains('.lat'), isFalse);
        expect(source.contains('.lng'), isFalse);
        expect(source.contains('avgWeightKg'), isFalse);
        expect(source.contains('totalWeightKg'), isFalse);
        expect(source.contains('totalGu'), isFalse);
        expect(source.contains('totalBu'), isFalse);
      }

      // The species screen knows nothing about camp size or capacity.
      expect(speciesSource.contains('totalSizeHa'), isFalse);
      expect(speciesSource.contains('capacityLsu'), isFalse);
    });

    test('the map screen is outfitter-only and reads through the owner-gated '
        'repository', () {
      final mapSource =
          File('lib/features/veld_carry/ui/veld_carry_camp_map_screen.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');

      // Owner-gated read only — no hunter-safe read on the map screen.
      expect(mapSource.contains('_repository.getCamps('), isTrue);
      expect(mapSource.contains('getCampsForHunter'), isFalse);
      expect(mapSource.contains('getStockForHunter'), isFalse);
      expect(mapSource.contains('getSpeciesAvailabilityForHunter'), isFalse);
      // Explicitly labelled outfitter-only.
      expect(mapSource.contains('Outfitter only'), isTrue);
      // Reuses the app's existing map widget rather than a new SDK.
      expect(mapSource.contains("package:flutter_map/flutter_map.dart"), isTrue);
    });

    test('the camp list exposes the map entry only behind the feature gate',
        () {
      final listSource =
          File('lib/features/veld_carry/ui/veld_carry_camp_list_screen.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');

      expect(listSource.contains('VeldCarryCampMapScreen'), isTrue);
      expect(listSource.contains("ValueKey('veldFarmMapButton')"), isTrue);
      // The map button sits inside a VeldCarryGate.
      final gateIndex = listSource.indexOf("ValueKey('veldFarmMapButton')");
      final precedingGate =
          listSource.substring(0, gateIndex).lastIndexOf('VeldCarryGate(');
      expect(precedingGate, greaterThan(-1));
    });
  });
}
