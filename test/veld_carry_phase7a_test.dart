import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_movement.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 7A contract tests — stock history / movements + rainfall log.
///
/// No real Firebase: the sign rules, the camp deltas and the below-zero guard
/// are pure, and the Firestore paths run against `FakeFirebaseFirestore`
/// through the repository's `forTesting` seam.
void main() {
  const uid = 'outfitter-1';
  const farmId = 'farm-1';
  const campA = 'camp-a';
  const campB = 'camp-b';

  VeldCarryRepository repo(FakeFirebaseFirestore db) =>
      VeldCarryRepository.forTesting(
        currentUserIdResolver: () => uid,
        firestore: db,
      );

  StockMovement movement({
    required String type,
    required int count,
    String campId = campA,
    String speciesId = 'greater_kudu',
    String speciesName = 'Greater Kudu',
    String? fromCampId,
    String? toCampId,
    String? reason,
  }) =>
      StockMovement(
        id: VeldCarryRepository.newId(),
        farmId: farmId,
        campId: campId,
        speciesId: speciesId,
        speciesName: speciesName,
        movementType: type,
        count: count,
        fromCampId: fromCampId,
        toCampId: toCampId,
        reason: reason,
        recordedBy: uid,
        recordedAt: DateTime(2026, 11, 20, 9),
      );

  Future<void> seedStock(
    FakeFirebaseFirestore db,
    String campId, {
    required int kudu,
    required int impala,
  }) async {
    final stock = db
        .collection('users')
        .doc(uid)
        .collection('farms')
        .doc(farmId)
        .collection('veldCamps')
        .doc(campId)
        .collection('stock');
    await stock.doc('greater_kudu').set(
          StockEntry(
            id: 'greater_kudu',
            campId: campId,
            speciesName: 'Greater Kudu',
            count: kudu,
            avgWeightKg: 250,
          ).toMap(),
        );
    await stock.doc('impala').set(
          StockEntry(
            id: 'impala',
            campId: campId,
            speciesName: 'Impala',
            count: impala,
            avgWeightKg: 50,
          ).toMap(),
        );
  }

  Future<StockEntry?> readStock(
    FakeFirebaseFirestore db,
    String campId,
    String speciesId,
  ) async {
    final snapshot = await db
        .collection('users')
        .doc(uid)
        .collection('farms')
        .doc(farmId)
        .collection('veldCamps')
        .doc(campId)
        .collection('stock')
        .doc(speciesId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return StockEntry.fromMap(data, id: snapshot.id);
  }

  group('movement sign validation', () {
    test('added requires a positive count', () {
      expect(
        StockMovement.isSignValid(StockMovement.typeAdded, 4),
        isTrue,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeAdded, -4),
        isFalse,
      );
      expect(
        movement(type: StockMovement.typeAdded, count: -4).validationError,
        isNotNull,
      );
    });

    test('moved_in requires positive, moved_out requires negative', () {
      expect(
        StockMovement.isSignValid(StockMovement.typeMovedIn, 3),
        isTrue,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeMovedIn, -3),
        isFalse,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeMovedOut, -3),
        isTrue,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeMovedOut, 3),
        isFalse,
      );
    });

    test('hunted / died / sold require a negative count', () {
      for (final type in [
        StockMovement.typeHunted,
        StockMovement.typeDied,
        StockMovement.typeSold,
      ]) {
        expect(StockMovement.isSignValid(type, -2), isTrue, reason: type);
        expect(StockMovement.isSignValid(type, 2), isFalse, reason: type);
      }
    });

    test('count_adjustment accepts either sign but never zero', () {
      expect(
        StockMovement.isSignValid(StockMovement.typeCountAdjustment, 5),
        isTrue,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeCountAdjustment, -5),
        isTrue,
      );
      expect(
        StockMovement.isSignValid(StockMovement.typeCountAdjustment, 0),
        isFalse,
      );
    });

    test('an unknown movement type is rejected', () {
      final invalid = movement(type: 'teleported', count: 2);
      expect(invalid.validationError, isNotNull);
      expect(StockMovement.isSignValid('teleported', 2), isFalse);
      expect(StockMovement.campDeltas(invalid), isEmpty);
    });

    test('hunted and died require a cause / notes entry', () {
      expect(
        movement(type: StockMovement.typeHunted, count: -1).validationError,
        isNotNull,
      );
      expect(
        movement(
          type: StockMovement.typeHunted,
          count: -1,
          reason: 'Wounded, tracked two days',
        ).validationError,
        isNull,
      );
      expect(StockMovement.requiresReason(StockMovement.typeSold), isFalse);
    });

    test('a move needs two distinct camps', () {
      final missing = movement(
        type: StockMovement.typeMovedOut,
        count: -2,
        fromCampId: campA,
      );
      expect(missing.validationError, isNotNull);
      final same = movement(
        type: StockMovement.typeMovedOut,
        count: -2,
        fromCampId: campA,
        toCampId: campA,
      );
      expect(same.validationError, isNotNull);
      final ok = movement(
        type: StockMovement.typeMovedOut,
        count: -2,
        fromCampId: campA,
        toCampId: campB,
      );
      expect(ok.validationError, isNull);
    });
  });

  group('camp deltas', () {
    test('a move touches two camps (source -, destination +)', () {
      final move = movement(
        type: StockMovement.typeMovedOut,
        count: -3,
        fromCampId: campA,
        toCampId: campB,
      );
      expect(StockMovement.campDeltas(move), {campA: -3, campB: 3});
    });

    test('moved_in produces the same two-camp deltas', () {
      final move = movement(
        type: StockMovement.typeMovedIn,
        count: 3,
        campId: campB,
        fromCampId: campA,
        toCampId: campB,
      );
      expect(StockMovement.campDeltas(move), {campA: -3, campB: 3});
    });

    test('hunted reduces one camp', () {
      final hunt = movement(type: StockMovement.typeHunted, count: -2);
      expect(StockMovement.campDeltas(hunt), {campA: -2});
    });

    test('added increases one camp', () {
      final added = movement(type: StockMovement.typeAdded, count: 7);
      expect(StockMovement.campDeltas(added), {campA: 7});
    });
  });

  group('applyDeltaToStockEntry', () {
    test('reduces the count and recomputes the derived totals', () {
      final entry = StockEntry(
        id: 'greater_kudu',
        campId: campA,
        speciesName: 'Greater Kudu',
        count: 5,
        avgWeightKg: 250,
        grazerPct: 0.3,
        browserPct: 0.7,
        lsuPerAnimal: lsuPerAnimal(250),
        guPerAnimal: guPerAnimal(250, 0.3),
        buPerAnimal: buPerAnimal(250, 0.7),
      );
      final reduced =
          StockMovement.applyDeltaToStockEntry(entry, -2, now: DateTime(2026));
      expect(reduced.count, 3);
      expect(reduced.totalWeightKg, 3 * 250);
      expect(reduced.totalLsu, lessThan(entry.totalLsu));
      expect(reduced.totalLsu, greaterThan(0));
    });

    test('throws instead of clamping when the result is negative', () {
      final entry = StockEntry(
        id: 'impala',
        campId: campA,
        speciesName: 'Impala',
        count: 1,
      );
      expect(
        () => StockMovement.applyDeltaToStockEntry(entry, -2),
        throwsA(isA<StockBelowZeroException>()),
      );
    });
  });

  group('recordStockMovement (Firestore)', () {
    test('a move updates BOTH camps', () async {
      final db = FakeFirebaseFirestore();
      await seedStock(db, campA, kudu: 10, impala: 4);
      await seedStock(db, campB, kudu: 2, impala: 0);
      final repository = repo(db);

      await repository.recordStockMovement(
        uid,
        movement(
          type: StockMovement.typeMovedOut,
          count: -3,
          fromCampId: campA,
          toCampId: campB,
        ),
      );

      expect((await readStock(db, campA, 'greater_kudu'))!.count, 7);
      expect((await readStock(db, campB, 'greater_kudu'))!.count, 5);
      // The untouched species is not disturbed.
      expect((await readStock(db, campA, 'impala'))!.count, 4);
    });

    test('hunted reduces the camp count by the movement magnitude', () async {
      final db = FakeFirebaseFirestore();
      await seedStock(db, campA, kudu: 6, impala: 3);
      final repository = repo(db);

      await repository.recordStockMovement(
        uid,
        movement(
          type: StockMovement.typeHunted,
          count: -2,
          reason: 'Biltong hunt',
        ),
      );

      expect((await readStock(db, campA, 'greater_kudu'))!.count, 4);
    });

    test('a movement can never take a camp below zero', () async {
      final db = FakeFirebaseFirestore();
      await seedStock(db, campA, kudu: 1, impala: 0);
      final repository = repo(db);

      await expectLater(
        repository.recordStockMovement(
          uid,
          movement(
            type: StockMovement.typeDied,
            count: -2,
            reason: 'Drought',
          ),
        ),
        throwsA(isA<StockBelowZeroException>()),
      );

      // Stock is untouched and no history row was written.
      expect((await readStock(db, campA, 'greater_kudu'))!.count, 1);
      expect(await repository.getStockMovements(uid, farmId), isEmpty);
    });

    test('a negative movement against a missing row is rejected', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      await expectLater(
        repository.recordStockMovement(
          uid,
          movement(
            type: StockMovement.typeSold,
            count: -1,
            speciesId: 'eland',
            speciesName: 'Eland',
          ),
        ),
        throwsA(isA<StockBelowZeroException>()),
      );
    });

    test('added creates the stock row from species_defaults', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);

      await repository.recordStockMovement(
        uid,
        movement(type: StockMovement.typeAdded, count: 8),
      );

      final entry = await readStock(db, campA, 'greater_kudu');
      expect(entry, isNotNull);
      expect(entry!.count, 8);
      expect(entry.avgWeightKg, greaterThan(0));
      expect(entry.totalLsu, greaterThan(0));
    });

    test('writes the camp history AND the farm-level mirror', () async {
      final db = FakeFirebaseFirestore();
      await seedStock(db, campA, kudu: 10, impala: 0);
      await seedStock(db, campB, kudu: 0, impala: 0);
      final repository = repo(db);

      final record = await repository.recordStockMovement(
        uid,
        movement(
          type: StockMovement.typeMovedOut,
          count: -2,
          fromCampId: campA,
          toCampId: campB,
        ),
      );

      final campHistory = await repository.getStockMovements(
        uid,
        farmId,
        campId: campA,
      );
      final farmHistory = await repository.getStockMovements(uid, farmId);
      final destinationHistory = await repository.getStockMovements(
        uid,
        farmId,
        campId: campB,
      );
      expect(campHistory.map((m) => m.id), contains(record.id));
      expect(farmHistory.map((m) => m.id), contains(record.id));
      expect(destinationHistory.map((m) => m.id), contains(record.id));
      expect(farmHistory.single.count, -2);
      expect(
        VeldCarryRepository.stockMovementPath(uid, farmId, campA, record.id),
        'users/$uid/farms/$farmId/veldCamps/$campA/stockHistory/${record.id}',
      );
      expect(
        VeldCarryRepository.farmStockMovementPath(uid, farmId, record.id),
        'users/$uid/farms/$farmId/stockHistory/${record.id}',
      );
    });

    test('history is returned newest first', () async {
      final db = FakeFirebaseFirestore();
      await seedStock(db, campA, kudu: 20, impala: 0);
      final repository = repo(db);

      final oldest = movement(
        type: StockMovement.typeHunted,
        count: -1,
        reason: 'First',
      ).copyWith(recordedAt: DateTime(2026, 1, 10));
      final middle = movement(
        type: StockMovement.typeHunted,
        count: -1,
        reason: 'Second',
      ).copyWith(recordedAt: DateTime(2026, 5, 10));
      final newest = movement(
        type: StockMovement.typeHunted,
        count: -1,
        reason: 'Third',
      ).copyWith(recordedAt: DateTime(2026, 9, 10));

      await repository.recordStockMovement(uid, oldest);
      await repository.recordStockMovement(uid, middle);
      await repository.recordStockMovement(uid, newest);

      final history = await repository.getStockMovements(
        uid,
        farmId,
        campId: campA,
      );
      expect(
        history.map((m) => m.reason),
        ['Third', 'Second', 'First'],
      );
    });

    test('an unauthenticated caller is rejected', () async {
      final db = FakeFirebaseFirestore();
      final anon = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => null,
        firestore: db,
      );
      await expectLater(
        anon.recordStockMovement(
          uid,
          movement(type: StockMovement.typeAdded, count: 1),
        ),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });

  group('stock entry id', () {
    test('matches the stock form slug', () {
      expect(
        VeldCarryRepository.speciesStockEntryId('Greater Kudu'),
        'greater_kudu',
      );
      expect(
        VeldCarryRepository.speciesStockEntryId('Common Warthog'),
        'common_warthog',
      );
    });
  });

  group('rainfall month validation', () {
    test('accepts YYYY-MM and rejects everything else', () {
      expect(RainfallEntry.isValidMonth('2026-11'), isTrue);
      expect(RainfallEntry.isValidMonth('2026-01'), isTrue);
      expect(RainfallEntry.isValidMonth('2026-12'), isTrue);
      expect(RainfallEntry.isValidMonth('2026-13'), isFalse);
      expect(RainfallEntry.isValidMonth('2026-00'), isFalse);
      expect(RainfallEntry.isValidMonth('2026-1'), isFalse);
      expect(RainfallEntry.isValidMonth('26-11'), isFalse);
      expect(RainfallEntry.isValidMonth('November 2026'), isFalse);
      expect(RainfallEntry.isValidMonth(''), isFalse);
      expect(RainfallEntry.isValidMonth(null), isFalse);
    });

    test('normalizeMonth trims and rejects malformed input', () {
      expect(RainfallEntry.normalizeMonth(' 2026-07 '), '2026-07');
      expect(RainfallEntry.normalizeMonth('2026-7'), isNull);
    });

    test('a malformed month fails validation', () {
      final entry = RainfallEntry(
        id: 'x',
        farmId: farmId,
        campId: campA,
        month: '2026-7',
        rainfallMm: 12,
      );
      expect(entry.validationError, isNotNull);
    });

    test('recentMonths walks back across a year boundary', () {
      final months =
          RainfallEntry.recentMonths(DateTime(2026, 2, 15), count: 3);
      expect(months, ['2026-02', '2026-01', '2025-12']);
    });
  });

  group('rainfall repository', () {
    test('saving the same month twice overwrites, never duplicates', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);

      await repository.saveRainfallEntry(
        uid,
        RainfallEntry(
          id: '2026-11',
          farmId: farmId,
          campId: campA,
          month: '2026-11',
          rainfallMm: 12.5,
        ),
      );
      await repository.saveRainfallEntry(
        uid,
        RainfallEntry(
          id: '2026-11',
          farmId: farmId,
          campId: campA,
          month: '2026-11',
          rainfallMm: 40.0,
        ),
      );

      final entries = await repository.getRainfallEntries(uid, farmId, campA);
      expect(entries, hasLength(1));
      expect(entries.single.month, '2026-11');
      expect(entries.single.rainfallMm, 40.0);
      expect(
        VeldCarryRepository.rainfallPath(uid, farmId, campA, '2026-11'),
        'users/$uid/farms/$farmId/veldCamps/$campA/rainfall/2026-11',
      );
    });

    test('a malformed month is rejected before the write', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      await expectLater(
        repository.saveRainfallEntry(
          uid,
          RainfallEntry(
            id: 'bad',
            farmId: farmId,
            campId: campA,
            month: '2026-7',
            rainfallMm: 10,
          ),
        ),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
      expect(await repository.getRainfallEntries(uid, farmId, campA), isEmpty);
    });

    test('a negative rainfall figure is rejected', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      await expectLater(
        repository.saveRainfallEntry(
          uid,
          RainfallEntry(
            id: '2026-11',
            farmId: farmId,
            campId: campA,
            month: '2026-11',
            rainfallMm: -5,
          ),
        ),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });

    test('entries come back newest month first', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      for (final month in ['2026-01', '2026-09', '2026-05']) {
        await repository.saveRainfallEntry(
          uid,
          RainfallEntry(
            id: month,
            farmId: farmId,
            campId: campA,
            month: month,
            rainfallMm: 10,
          ),
        );
      }
      final entries = await repository.getRainfallEntries(uid, farmId, campA);
      expect(entries.map((e) => e.month), ['2026-09', '2026-05', '2026-01']);
    });

    test('getRainfallTotalForYear sums only that calendar year', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      for (final month in ['2025-12', '2026-01', '2026-02', '2026-03']) {
        await repository.saveRainfallEntry(
          uid,
          RainfallEntry(
            id: month,
            farmId: farmId,
            campId: campA,
            month: month,
            rainfallMm: 10,
          ),
        );
      }
      expect(
        await repository.getRainfallTotalForYear(
          uid,
          farmId,
          campA,
          year: 2026,
        ),
        30,
      );
      expect(
        await repository.getRainfallTotalForYear(
          uid,
          farmId,
          campA,
          year: 2025,
        ),
        10,
      );
    });
  });

  group('rainfall maths', () {
    RainfallEntry entry(String month, double mm) => RainfallEntry(
          id: month,
          farmId: farmId,
          campId: campA,
          month: month,
          rainfallMm: mm,
        );

    test('trailing 12-month total ignores older months', () {
      final entries = [
        entry('2026-11', 10),
        entry('2026-10', 20),
        entry('2025-12', 5),
        entry('2025-11', 100),
      ];
      // The window is 2025-12 .. 2026-11 inclusive: 2025-11 is 13 months back
      // and must not count.
      expect(
        rainfallTotalLastTwelveMonths(entries, now: DateTime(2026, 11, 15)),
        35,
      );
    });

    test('calendar-year total and overall total', () {
      final entries = [
        entry('2026-01', 12.5),
        entry('2026-02', 7.5),
        entry('2025-12', 4),
      ];
      expect(rainfallTotalForYear(entries, 2026), 20);
      expect(rainfallTotalMm(entries), 24);
    });

    test('the condition hint compares against the camp own annual figure', () {
      expect(
        rainfallConditionSuggestion(
          last12MonthsMm: 460,
          expectedAnnualMm: 480,
        ),
        'good',
      );
      expect(
        rainfallConditionSuggestion(
          last12MonthsMm: 300,
          expectedAnnualMm: 480,
        ),
        'fair',
      );
      expect(
        rainfallConditionSuggestion(
          last12MonthsMm: 120,
          expectedAnnualMm: 480,
        ),
        'poor',
      );
      // No expected figure -> no invented guess.
      expect(
        rainfallConditionSuggestion(
          last12MonthsMm: 300,
          expectedAnnualMm: null,
        ),
        isNull,
      );
    });
  });

  group('model round trips', () {
    test('StockMovement survives toMap/fromMap', () {
      final original = movement(
        type: StockMovement.typeMovedOut,
        count: -4,
        fromCampId: campA,
        toCampId: campB,
        reason: 'Rotational grazing',
      );
      final restored = StockMovement.fromMap(original.toMap());
      expect(restored, original);
      expect(restored.signedCountLabel, '-4');
      expect(restored.isMove, isTrue);
    });

    test('RainfallEntry survives toMap/fromMap', () {
      final original = RainfallEntry(
        id: '2026-11',
        farmId: farmId,
        campId: campA,
        month: '2026-11',
        rainfallMm: 42.5,
        recordedBy: uid,
      );
      final restored = RainfallEntry.fromMap(original.toMap());
      expect(restored, original);
      expect(restored.monthLabel, 'Nov 2026');
      expect(restored.year, 2026);
      expect(restored.monthNumber, 11);
    });
  });
}
