import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_list_screen.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 7D contract tests — booking hardening + species verification.
///
/// Two concerns:
///
///  1. **Booking hardening.** `syncAllowedHuntersForFarm` denormalises the
///     farm's Confirmed / Completed bookings onto every camp as
///     `allowedHunterUids`, so the go-live Firestore rule can gate a hunter
///     read without reading the `bookings` collection.
///  2. **Species verification.** Every row of the 49-species table carries an
///     explicit verification status + citable source; the one corrected weight
///     and the one unverified row are pinned by test.
///
/// No real Firebase: Firestore runs against `FakeFirebaseFirestore` through the
/// repository's `forTesting` seam, and the species rules are pure.
void main() {
  const outfitterUid = 'outfitter-1';
  const hunterUid = 'hunter-1';
  const otherHunterUid = 'hunter-2';
  const farmId = 'farm-1';
  const otherFarmId = 'farm-2';
  const campId = 'camp-1';
  const secondCampId = 'camp-2';

  final theme = ThemeController();

  VeldCarryRepository ownerRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(
        currentUserIdResolver: () => outfitterUid,
        firestore: firestore,
      );

  /// A hunter is not the farm's outfitter: no uid resolver, so an ownership
  /// check would throw.
  VeldCarryRepository hunterRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(firestore: firestore);

  Camp camp({String id = campId, String name = 'North Camp', String? farm}) =>
      Camp(
        id: id,
        farmId: farm ?? farmId,
        name: name,
        totalSizeHa: 1000,
        province: 'Limpopo',
        district: 'Waterberg',
        veldType: 'Sweetveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 10,
      );

  /// Seeds a camp directly (the repository's own writes are covered by earlier
  /// phases; here we only need the document shape the sync reads).
  Future<void> seedCamp(
    FakeFirebaseFirestore firestore,
    Camp value, {
    List<String>? allowed,
  }) async {
    final data = Map<String, dynamic>.from(value.toMap());
    if (allowed != null) {
      data[Camp.allowedHunterUidsField] = allowed;
    }
    await firestore
        .collection(VeldCarryRepository.usersCollection)
        .doc(outfitterUid)
        .collection(VeldCarryRepository.farmsCollection)
        .doc(value.farmId)
        .collection(VeldCarryRepository.campsCollection)
        .doc(value.id)
        .set(data);
  }

  Future<void> seedBooking(
    FakeFirebaseFirestore firestore, {
    required String hunter,
    required String status,
    String farm = farmId,
    String id = '',
  }) async {
    final docId = id.isEmpty ? 'booking-$hunter-$farm-$status' : id;
    await firestore.collection('bookings').doc(docId).set({
      'hunterId': hunter,
      'outfitterId': outfitterUid,
      'farmId': farm,
      'status': status,
    });
  }

  Future<List<String>> allowedOn(
    FakeFirebaseFirestore firestore,
    String camp,
  ) async {
    final snap = await firestore
        .collection(VeldCarryRepository.usersCollection)
        .doc(outfitterUid)
        .collection(VeldCarryRepository.farmsCollection)
        .doc(farmId)
        .collection(VeldCarryRepository.campsCollection)
        .doc(camp)
        .get();
    return Camp.normalizeAllowedHunterUids(
      snap.data()?[Camp.allowedHunterUidsField],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 1. CAMP MODEL
  // ══════════════════════════════════════════════════════════════════════
  group('Camp.allowedHunterUids', () {
    test('round-trips through toMap / fromMap', () {
      final withList = camp().copyWith(allowedHunterUids: [hunterUid, 'u-2']);
      final map = withList.toMap();

      expect(map[Camp.allowedHunterUidsField], [hunterUid, 'u-2']);
      final restored = Camp.fromMap(map, id: campId);
      expect(restored.allowedHunterUids, [hunterUid, 'u-2']);
    });

    test('toMap OMITS the field when empty so a camp edit cannot wipe it', () {
      // The camp form builds a fresh Camp, so an empty list must not be written
      // back over a previously synced allow-list.
      expect(camp().toMap().containsKey(Camp.allowedHunterUidsField), isFalse);
    });

    test('normalises any stored shape — missing, non-list, blanks, dupes', () {
      expect(Camp.normalizeAllowedHunterUids(null), isEmpty);
      expect(Camp.normalizeAllowedHunterUids('  '), isEmpty);
      expect(Camp.normalizeAllowedHunterUids(42), isEmpty);
      expect(
        Camp.normalizeAllowedHunterUids([' a ', 'a', '', null, 'b']),
        ['a', 'b'],
      );
      // A lone string is treated as one uid rather than throwing.
      expect(Camp.normalizeAllowedHunterUids(' u-9 '), ['u-9']);
    });

    test('copyWith keeps the list and equality is order-insensitive', () {
      final base = camp().copyWith(allowedHunterUids: [hunterUid, 'u-2']);
      expect(base.copyWith(name: 'South Camp').allowedHunterUids,
          [hunterUid, 'u-2']);
      // `Camp` fixes createdAt/updatedAt at construction, so equality is
      // asserted through copyWith from the SAME base.
      expect(base, base.copyWith(allowedHunterUids: ['u-2', hunterUid]));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2. SYNC
  // ══════════════════════════════════════════════════════════════════════
  group('syncAllowedHuntersForFarm', () {
    test('collects Confirmed + Completed only, onto EVERY camp of the farm',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      await seedCamp(firestore, camp(id: secondCampId, name: 'South Camp'));

      await seedBooking(firestore,
          hunter: hunterUid, status: BookingStatus.confirmed);
      await seedBooking(
        firestore,
        hunter: otherHunterUid,
        status: BookingStatus.completed,
      );
      // None of these may grant access.
      for (final status in const [
        BookingStatus.pendingApproval,
        BookingStatus.approvedAwaitingPayment,
        BookingStatus.declined,
        BookingStatus.cancelled,
      ]) {
        await seedBooking(
          firestore,
          hunter: 'nope-$status',
          status: status,
        );
      }

      final result =
          await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);

      expect(result.hunterUids, containsAll([hunterUid, otherHunterUid]));
      expect(result.hunterUids, hasLength(2));
      expect(result.campCount, 2);
      expect(result.campsTouched, 2);

      for (final id in const [campId, secondCampId]) {
        final allowed = await allowedOn(firestore, id);
        expect(allowed, containsAll([hunterUid, otherHunterUid]), reason: id);
        expect(allowed, hasLength(2), reason: id);
      }
    });

    test(
        'arrayUnion semantics — re-running adds no duplicate and drops nothing',
        () async {
      final firestore = FakeFirebaseFirestore();
      // A camp that already carries an entry (e.g. a hunter from an earlier
      // booking that has since lapsed).
      await seedCamp(firestore, camp(), allowed: const ['legacy-hunter']);
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.confirmed,
      );

      await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);
      final first = await allowedOn(firestore, campId);
      expect(first, containsAll(['legacy-hunter', hunterUid]));

      // Second run: no duplicate, nothing dropped.
      final second =
          await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);
      final after = await allowedOn(firestore, campId);
      expect(after, first);
      expect(after.where((uid) => uid == hunterUid), hasLength(1));
      expect(after, contains('legacy-hunter'));
      // Nothing new to write -> reported as already in sync.
      expect(second.campsTouched, 0);
    });

    test('a hunter without a booking gets an EMPTY allow-list (fail closed)',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      // Only a pending booking, which never grants access.
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.pendingApproval,
      );

      final result =
          await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);

      expect(result.hasHunters, isFalse);
      expect(result.hunterUids, isEmpty);
      expect(await allowedOn(firestore, campId), isEmpty);
      // The field is still seeded as a list so the rule evaluates a list
      // instead of a missing property.
      final snap = await firestore
          .collection(VeldCarryRepository.usersCollection)
          .doc(outfitterUid)
          .collection(VeldCarryRepository.farmsCollection)
          .doc(farmId)
          .collection(VeldCarryRepository.campsCollection)
          .doc(campId)
          .get();
      expect(
        snap.data()!.containsKey(Camp.allowedHunterUidsField),
        isTrue,
      );
      expect(
        snap.data()![Camp.allowedHunterUidsField],
        isA<List<dynamic>>(),
      );

      // And the hunter read is still refused by the code gate.
      expect(
        await hunterRepo(firestore).getCampsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isEmpty,
      );
    });

    test('a hunter named in allowedHunterUids (with a booking) gets the data',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.confirmed,
      );

      await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);
      expect(await allowedOn(firestore, campId), contains(hunterUid));

      // The rules-level allow-list and the code-side gate now agree.
      expect(
        await hunterRepo(firestore).hunterHasBookingForFarm(hunterUid, farmId),
        isTrue,
      );
      final camps = await hunterRepo(firestore).getCampsForHunter(
        farmId,
        outfitterUid: outfitterUid,
        hunterUid: hunterUid,
      );
      expect(camps, hasLength(1));
      expect(camps.single.name, 'North Camp');
    });

    test('other farms\' bookings never leak into the allow-list', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.confirmed,
        farm: farmId,
      );
      await seedBooking(
        firestore,
        hunter: otherHunterUid,
        status: BookingStatus.confirmed,
        farm: otherFarmId,
      );

      final result =
          await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);

      expect(result.hunterUids, [hunterUid]);
      expect(await allowedOn(firestore, campId), [hunterUid]);
    });

    test('a non-owner cannot touch the owner\'s allow-list', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.confirmed,
      );

      // No signed-in user at all: refused before any read or write.
      await expectLater(
        hunterRepo(firestore).syncAllowedHuntersForFarm(farmId),
        throwsA(isA<VeldCarryRepositoryException>()),
      );

      // Signed in as somebody else: the ownership guard rejects an explicit
      // write addressed at the real outfitter.
      final impostor = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'someone-else',
        firestore: firestore,
      );
      expect(
        () => impostor.requireOwnership(outfitterUid),
        throwsA(isA<VeldCarryOwnershipException>()),
      );

      // And a sync run by that user is scoped to THEIR OWN document — the real
      // outfitter's camps are never written.
      final result = await impostor.syncAllowedHuntersForFarm(farmId);
      expect(result.campsTouched, 0);
      expect(await allowedOn(firestore, campId), isEmpty);
    });

    test('mergeAllowedHunterUids is a pure union (no duplicates, order kept)',
        () {
      expect(
        VeldCarryRepository.mergeAllowedHunterUids(
          ['a', 'b'],
          ['b', 'c', ' a '],
        ),
        ['a', 'b', 'c'],
      );
      expect(VeldCarryRepository.mergeAllowedHunterUids(null, ['a']), ['a']);
      expect(VeldCarryRepository.mergeAllowedHunterUids(['a'], null), ['a']);
      expect(VeldCarryRepository.mergeAllowedHunterUids(null, null), isEmpty);
    });

    test('the sync result summarises what happened', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());
      await seedBooking(
        firestore,
        hunter: hunterUid,
        status: BookingStatus.confirmed,
      );

      final result =
          await ownerRepo(firestore).syncAllowedHuntersForFarm(farmId);
      expect(result.summary, '1 hunter · 1 camp (1 updated)');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 3. SPECIES VERIFICATION
  // ══════════════════════════════════════════════════════════════════════
  group('species table verification', () {
    test('every row carries a verification status AND a source', () {
      expect(speciesDefaults, hasLength(49));
      for (final species in speciesDefaults) {
        expect(
          species.verificationSource.trim(),
          isNotEmpty,
          reason: '${species.speciesName} must state its verification status',
        );
      }
    });

    test('Cape Hare is the ONLY unverified row, and it explains why', () {
      final unverified = speciesDefaults
          .where((species) => !species.isVerified)
          .map((species) => species.speciesName)
          .toList();
      expect(unverified, ['Cape Hare']);

      final capeHare = speciesDefaultFor('Cape Hare')!;
      expect(capeHare.isVerified, isFalse);
      expect(capeHare.avgWeightKg, 2.0, reason: 'fallback retained');
      expect(capeHare.verificationSource, contains('UNVERIFIED'));
      expect(capeHare.verificationSource, contains('species complex'));
    });

    test('the one corrected weight is Cane Rat 8 kg -> 4.5 kg', () {
      final caneRat = speciesDefaultFor('Cane Rat')!;
      expect(caneRat.avgWeightKg, 4.5);
      expect(caneRat.isVerified, isTrue);
      expect(caneRat.verificationSource, contains('Greater cane rat'));
      // The correction is recorded in the source text so it is auditable.
      expect(caneRat.verificationSource, contains('was 8 kg'));
    });

    test('the three Phase-6 flagged species are verified at the same weights',
        () {
      final elephant = speciesDefaultFor('African Elephant')!;
      expect(elephant.avgWeightKg, 4500);
      expect(elephant.isVerified, isTrue);
      expect(elephant.verificationSource, contains('African bush elephant'));

      final giraffe = speciesDefaultFor('Giraffe')!;
      expect(giraffe.avgWeightKg, 1100);
      expect(giraffe.isVerified, isTrue);

      final hippo = speciesDefaultFor('Hippopotamus')!;
      expect(hippo.avgWeightKg, 1500);
      expect(hippo.isVerified, isTrue);
    });

    test('no grazer/browser split was changed', () {
      for (final species in speciesDefaults) {
        if (!species.isCounted) {
          expect(species.isCounted, isFalse, reason: species.speciesName);
        }
        if (!species.hasKnownWeight) continue;
        if (species.speciesName == 'Aardvark') continue; // documented 0 / 0
        expect(
          species.grazerPct + species.browserPct,
          closeTo(1.0, 1e-9),
          reason: species.speciesName,
        );
      }
      // Pure grazers / browsers still sit at the ends of the spectrum.
      expect(speciesDefaultFor('Plains Zebra')!.grazerPct, 1.0);
      expect(speciesDefaultFor('Giraffe')!.browserPct, 0.95);
    });

    test('the LSU maths is unchanged for an untouched row', () {
      final impala = speciesDefaultFor('Impala')!;
      expect(impala.avgWeightKg, 55);
      expect(lsuPerAnimal(impala.avgWeightKg), closeTo(0.2066, 0.001));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 4. UI — manual sync is the ONLY trigger
  // ══════════════════════════════════════════════════════════════════════
  group('manual "Sync hunter access" action', () {
    testWidgets('renders when the flag is ON and not when it is OFF',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());

      const key = ValueKey('veldSyncHunterAccessButton');

      // Flag OFF (the default build): nothing renders, no Firestore read.
      await tester.pumpWidget(
        MaterialApp(
          home: VeldCarryCampListScreen(
            farmId: farmId,
            farmName: 'Bosveld Ranch',
            theme: theme,
            repository: ownerRepo(firestore),
            flag: VeldCarryFeatureFlag.forTesting(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);

      // Dispose the flag-OFF tree first: the gates keep their State (and their
      // resolved flag) when the same widget position is reused.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Flag ON: the dedicated sync action is present.
      await tester.pumpWidget(
        MaterialApp(
          home: VeldCarryCampListScreen(
            farmId: farmId,
            farmName: 'Bosveld Ranch',
            theme: theme,
            repository: ownerRepo(firestore),
            flag: VeldCarryFeatureFlag.forTesting(
              compileTimeEnabled: true,
              adminConfigEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);
      expect(
        find.byTooltip('Sync hunter access (confirmed bookings)'),
        findsOneWidget,
      );
    });

    testWidgets('tapping it runs the handler (sign-in guard)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp());

      await tester.pumpWidget(
        MaterialApp(
          home: VeldCarryCampListScreen(
            farmId: farmId,
            farmName: 'Bosveld Ranch',
            theme: theme,
            // Owner repo: the sync would succeed, but the test host has no
            // signed-in Firebase user, so the guard fires first.
            repository: ownerRepo(firestore),
            flag: VeldCarryFeatureFlag.forTesting(
              compileTimeEnabled: true,
              adminConfigEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('veldSyncHunterAccessButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('You must be signed in to sync hunter access.'),
        findsOneWidget,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 5. RULES FRAGMENT + LIVE RULES UNTOUCHED
  // ══════════════════════════════════════════════════════════════════════
  group('go-live rules fragment', () {
    final rules = File('firestore.rules.veld_carry.GO_LIVE_READY')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('every veld hunter read gates on allowedHunterUids', () {
      expect(rules, contains('allowedHunterUids'));
      // camps
      expect(
        rules,
        contains('request.auth.uid in resource.data.allowedHunterUids'),
      );
      // stock + plantedAreas resolve it from the parent camp
      expect(rules, contains('function isAllowedCamper('));
      expect(
          rules, contains('|| isAllowedCamper(outfitterUid, farmId, campId)'));
    });

    test('the old isSignedIn() hunter read is kept as a commented fallback',
        () {
      final fallbacks =
          '// allow read: if isSignedIn();'.allMatches(rules).length;
      expect(fallbacks, greaterThanOrEqualTo(3));
      // No ACTIVE bare-signed-in read grant survives in the veld blocks.
      expect(rules, isNot(contains('\n      allow read: if isSignedIn();')));
    });

    test('the permits allow-list variant is documented but NOT enabled', () {
      expect(
        rules,
        contains('//         && request.auth.uid in '
            'resource.data.allowedHunterUids);'),
      );
      // Permits still read on the Phase 6 visibility gate.
      expect(
        rules,
        contains(
          "|| (isSignedIn() && resource.data.visibility == "
          "'hunter_visible');",
        ),
      );
    });

    test('the LIVE firestore.rules carries the veld blocks + allow-list gate',
        () {
      // 399ebbf synced the GO_LIVE_READY fragment into the live ruleset, so the
      // former "live rules untouched" assertion is obsolete. Assert the live
      // rules now enforce the same hunter contract the fragment documents.
      final live =
          File('firestore.rules').readAsStringSync().replaceAll('\r\n', '\n');
      expect(live, contains('veldCamps'));
      expect(live, contains('allowedHunterUids'));
      expect(
        live,
        contains('request.auth.uid in resource.data.allowedHunterUids'),
      );
      expect(live, contains('function isAllowedCamper('));
    });
  });
}
