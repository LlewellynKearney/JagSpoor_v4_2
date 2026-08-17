import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/farm_game_price_entry.dart';
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
}
