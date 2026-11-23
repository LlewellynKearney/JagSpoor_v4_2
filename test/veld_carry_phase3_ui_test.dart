import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_detail_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_planted_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_predator_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_stock_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 3 UI contract tests: stock, planted feed and predator capture plus the
/// camp-detail summary.
///
/// Every capacity number asserted here is produced by
/// `veld_carry_calculator.dart`; these tests pin the wiring (which inputs reach
/// the calculator) rather than re-deriving the formulas.
void main() {
  const uid = 'outfitter-1';
  const farmId = 'farm-1';
  const campId = 'camp-1';

  final theme = ThemeController();

  VeldCarryRepository repo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(
        currentUserIdResolver: () => uid,
        firestore: firestore,
      );

  Camp buildCamp({
    double totalSizeHa = 1000,
    double deptNormHaPerLsu = 10,
    String veldCondition = Camp.veldConditionGood,
  }) =>
      Camp(
        id: campId,
        farmId: farmId,
        name: 'North Camp',
        totalSizeHa: totalSizeHa,
        province: 'Limpopo',
        district: 'Waterberg',
        veldType: 'Sweetveld',
        veldCondition: veldCondition,
        deptNormHaPerLsu: deptNormHaPerLsu,
      );

  Widget host(Widget child) =>
      MaterialApp(theme: ThemeData.light(), home: child);

  /// Pumps [child] on a tall surface so every lazily-built list child exists.
  ///
  /// The detail screen and the planted form both stack more content than the
  /// default 800x600 surface can hold, and a ListView only builds what is
  /// visible — a short surface would make "not found" mean "not scrolled to".
  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(child));
    await tester.pumpAndSettle();
  }

  // ── 1. Species picker excludes every weight-0 placeholder ─────────────
  group('stock species picker', () {
    test('offers only species with an authorised weight', () {
      final selectable = veldCarrySelectableStockSpecies();

      expect(selectable, isNotEmpty);
      expect(
        selectable.every((species) => species.avgWeightKg > 0),
        isTrue,
        reason: 'a 0 kg row would always produce 0 LSU',
      );

      final offered =
          selectable.map((s) => s.speciesName.toLowerCase()).toSet();
      for (final missing in missingSpeciesNames) {
        expect(
          offered.contains(missing.toLowerCase()),
          isFalse,
          reason: '$missing has no authorised weight and must not be offered',
        );
      }
      expect(
        missingSpecies.every((species) => species.avgWeightKg == 0),
        isTrue,
      );
    });

    testWidgets('the dropdown never renders a weight-0 species',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        host(
          VeldCarryStockFormScreen(
            farmId: farmId,
            campId: campId,
            theme: theme,
            repository: repo(firestore),
            currentUidOverride: uid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      final values = dropdown.items!.map((item) => item.value!).toSet();

      expect(values.length, veldCarrySelectableStockSpecies().length);
      expect(values.contains('Impala'), isTrue);
      // A documented placeholder species must be absent from the picker.
      expect(values.contains('Yellow Mongoose'), isFalse);
    });
  });

  // ── 2. Present-only species forces 0 LSU ──────────────────────────────
  group('present-only species', () {
    test('the StockEntry factory zeroes every counted total', () {
      final baboon = StockEntry(
        id: 'chacma_baboon',
        campId: campId,
        speciesName: 'Chacma Baboon',
        count: 12,
        avgWeightKg: 25,
        isCounted: false,
      );

      expect(baboon.isCounted, isFalse);
      expect(baboon.totalLsu, 0.0);
      expect(baboon.totalGu, 0.0);
      expect(baboon.totalBu, 0.0);
      expect(baboon.totalWeightKg, 0.0);
    });

    testWidgets('a present-only row shows the banner and previews 0 LSU',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final existing = StockEntry(
        id: 'chacma_baboon',
        campId: campId,
        speciesName: 'Chacma Baboon',
        count: 12,
        avgWeightKg: 25,
        isCounted: false,
      );

      await tester.pumpWidget(
        host(
          VeldCarryStockFormScreen(
            farmId: farmId,
            campId: campId,
            existingEntry: existing,
            theme: theme,
            repository: repo(firestore),
            currentUidOverride: uid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('veldStockPresentOnlyBanner')),
        findsOneWidget,
      );

      await tester.enterText(
          find.byKey(const ValueKey('veldStockCountField')), '20');
      await tester.pumpAndSettle();

      // Even with 20 animals present, the preview must stay at zero.
      final previewTexts = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('veldStockPreview')),
            matching: find.byType(Text),
          ))
          .map((text) => text.data)
          .toList();
      expect(previewTexts.where((t) => t == '0.0 LSU').length, 3);
    });
  });

  // ── 3. Grazer + browser split validation ──────────────────────────────
  group('grazer / browser split', () {
    testWidgets('a split that does not sum to 1.0 is rejected', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final existing = StockEntry(
        id: 'impala',
        campId: campId,
        speciesName: 'Impala',
        feedingClass: StockEntry.feedingClassMixed,
        count: 10,
        avgWeightKg: 55,
        grazerPct: 0.6,
        browserPct: 0.4,
      );

      await tester.pumpWidget(
        host(
          VeldCarryStockFormScreen(
            farmId: farmId,
            campId: campId,
            existingEntry: existing,
            theme: theme,
            repository: repo(firestore),
            currentUidOverride: uid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The prefilled split is valid, so no error is shown.
      expect(find.byKey(const ValueKey('veldStockSplitError')), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey('veldStockGrazerField')), '0.6');
      await tester.enterText(
          find.byKey(const ValueKey('veldStockBrowserField')), '0.6');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('veldStockSplitError')), findsOneWidget);

      // Correcting the split clears the error.
      await tester.enterText(
          find.byKey(const ValueKey('veldStockBrowserField')), '0.4');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('veldStockSplitError')), findsNothing);
    });
  });

  // ── 4. Planted capacity preview ───────────────────────────────────────
  group('planted feed', () {
    test('capacity is area divided by hectares-per-LSU', () {
      // Lucerne (irrigated) is published at 1.0 ha/LSU.
      expect(plantedCapacityLsu(10, 1.0), 10.0);
      // Kikuyu (irrigated) is 0.20 ha/LSU, so 10 ha carries 50 LSU.
      expect(plantedCapacityLsu(10, 0.20), closeTo(50.0, 1e-9));
      expect(plantedCapacityLsu(0, 1.0), 0.0);
    });

    testWidgets('the preview reflects the area and the published norm',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await pumpTall(
        tester,
        VeldCarryPlantedFormScreen(
          farmId: farmId,
          campId: campId,
          theme: theme,
          repository: repo(firestore),
          currentUidOverride: uid,
        ),
      );

      // The default feed type is Lucerne (irrigated): 1.0 ha/LSU.
      await tester.enterText(
          find.byKey(const ValueKey('veldPlantedAreaField')), '12');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('veldPlantedCapacityPreview')),
          matching: find.text('12.0 LSU'),
        ),
        findsOneWidget,
      );
    });
  });

  // ── 5. Predator prey-impact preview ───────────────────────────────────
  group('predator prey impact', () {
    test('prey maths follows the published daily intake', () {
      final preyKg = preyKgPerYear(2, 7.0);
      expect(preyKg, closeTo(2 * 7.0 * 365, 1e-9));
      expect(preyAnimalsPerYear(preyKg, 50), closeTo(preyKg / 50, 1e-9));

      // Predators never add LSU.
      final lion = PredatorEntry(
        id: 'lion',
        campId: campId,
        predatorName: 'Lion',
        count: 2,
        dailyIntakeKg: 7.0,
      );
      expect(lion.totalLsu, 0.0);
      expect(lion.totalGu, 0.0);
      expect(lion.totalBu, 0.0);
    });

    testWidgets('the preview shows kg and animals per year', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        host(
          VeldCarryPredatorFormScreen(
            farmId: farmId,
            campId: campId,
            theme: theme,
            repository: repo(firestore),
            currentUidOverride: uid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The default selection is the first published predator (Lion, 7 kg/day).
      await tester.enterText(
          find.byKey(const ValueKey('veldPredatorCountField')), '2');
      await tester.pumpAndSettle();

      // 2 lions x 7 kg x 365 days = 5110 kg; at 50 kg prey that is 102.2.
      expect(find.text('5110 kg'), findsOneWidget);
      expect(find.text('102'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('veldPredatorInfoBanner')),
        findsOneWidget,
      );
    });
  });

  // ── 6. Camp detail totals: stock + planted + usage ────────────────────
  group('camp detail summary', () {
    testWidgets('totals combine veld capacity, planted areas and stock',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repository = repo(firestore);

      // Camp: 1000 ha at 10 ha/LSU, good condition -> 100 LSU veld capacity.
      final camp = buildCamp();
      final campRef = firestore
          .collection('users')
          .doc(uid)
          .collection('farms')
          .doc(farmId)
          .collection('veldCamps')
          .doc(campId);
      await campRef.set(camp.toMap());

      // 5 ha of year-round Lucerne (irrigated) at 1.0 ha/LSU -> 5 LSU.
      final planted = PlantedArea(
        id: 'planted-1',
        campId: campId,
        feedType: PlantedArea.feedTypeLucerneIrrigated,
        areaHa: 5,
        haPerLsu: 1.0,
        season: PlantedArea.seasonAllYear,
      );
      await campRef
          .collection('plantedAreas')
          .doc(planted.id)
          .set(planted.toMap());

      // 10 Impala at 55 kg — LSU per animal comes from the calculator.
      final impala = StockEntry(
        id: 'impala',
        campId: campId,
        speciesName: 'Impala',
        feedingClass: StockEntry.feedingClassMixed,
        count: 10,
        avgWeightKg: 55,
        grazerPct: 0.6,
        browserPct: 0.4,
        lsuPerAnimal: lsuPerAnimal(55),
        guPerAnimal: guPerAnimal(55, 0.6),
        buPerAnimal: buPerAnimal(55, 0.4),
      );
      await campRef.collection('stock').doc(impala.id).set(impala.toMap());

      // A present-only species must not move the totals.
      final baboon = StockEntry(
        id: 'baboon',
        campId: campId,
        speciesName: 'Chacma Baboon',
        count: 30,
        avgWeightKg: 25,
        isCounted: false,
      );
      await campRef.collection('stock').doc(baboon.id).set(baboon.toMap());

      const expectedTotal = 105.0;
      final stockLsu = impala.totalLsu;

      await pumpTall(
        tester,
        VeldCarryCampDetailScreen(
          camp: camp,
          farmId: farmId,
          farmName: 'Bosveld Ranch',
          theme: theme,
          repository: repository,
          currentUidOverride: uid,
        ),
      );

      // Veld 100 LSU, planted 5 LSU, total 105 LSU.
      expect(find.text('100.0 LSU'), findsWidgets);
      expect(find.text('5.0 LSU'), findsWidgets);
      expect(find.text('105.0 LSU'), findsWidgets);
      expect(find.text(formatLsu(stockLsu)), findsWidgets);

      // Usage is stock / total; with this little stock the camp is
      // understocked. The present-only baboons contribute nothing.
      final usage = usagePct(stockLsu, expectedTotal);
      expect(find.text(formatUsagePct(usage)), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('veldCampStockingBadge')),
          matching: find.text('Understocked'),
        ),
        findsOneWidget,
      );

      // The present-only species is listed separately, never in the totals.
      expect(find.textContaining('PRESENT, NOT COUNTED'), findsOneWidget);
      expect(find.byKey(const ValueKey('veldPresentOnlyRow_baboon')),
          findsOneWidget);
    });

    testWidgets('a camp with no stock reports 0% and understocked',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await pumpTall(
        tester,
        VeldCarryCampDetailScreen(
          camp: buildCamp(),
          farmId: farmId,
          theme: theme,
          repository: repo(firestore),
          currentUidOverride: uid,
        ),
      );

      expect(find.text('0.0%'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('veldCampStockingBadge')),
          matching: find.text('Understocked'),
        ),
        findsOneWidget,
      );
      // Capacity still resolves from the camp alone.
      expect(find.text('100.0 LSU'), findsWidgets);
    });

    testWidgets('the three sections expose an Add action each', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await pumpTall(
        tester,
        VeldCarryCampDetailScreen(
          camp: buildCamp(),
          farmId: farmId,
          theme: theme,
          repository: repo(firestore),
          currentUidOverride: uid,
        ),
      );

      expect(find.byKey(const ValueKey('veldCampAddStockButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('veldCampAddPlantedButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('veldCampAddPredatorButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('veldCampEditButton')), findsOneWidget);
    });
  });

  // ── 7. Repository child-record round-trip + deletes ───────────────────
  group('repository child records', () {
    test('planted areas and predators round-trip and sort by name', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = repo(firestore);

      await repository.savePlantedArea(
        uid,
        farmId,
        campId,
        PlantedArea(
          id: 'b',
          campId: campId,
          feedType: PlantedArea.feedTypeTeff,
          areaHa: 3,
          haPerLsu: 1.5,
        ),
      );
      await repository.savePlantedArea(
        uid,
        farmId,
        campId,
        PlantedArea(
          id: 'a',
          campId: campId,
          feedType: PlantedArea.feedTypeLucerneIrrigated,
          areaHa: 4,
          haPerLsu: 1.0,
        ),
      );
      await repository.savePredatorEntry(
        uid,
        farmId,
        campId,
        PredatorEntry(
          id: 'p1',
          campId: campId,
          predatorName: 'Leopard',
          count: 1,
          dailyIntakeKg: 4.0,
        ),
      );

      final planted = await repository.getPlantedAreas(uid, farmId, campId);
      final predators = await repository.getPredators(uid, farmId, campId);

      expect(planted.map((a) => a.feedType).toList(),
          [PlantedArea.feedTypeLucerneIrrigated, PlantedArea.feedTypeTeff]);
      expect(predators.single.predatorName, 'Leopard');
      expect(predators.single.preyKgPerYear, closeTo(4.0 * 365, 1e-9));
    });

    test('deleting the camp children and the camp leaves nothing behind',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = repo(firestore);
      final camp = buildCamp();

      await repository.saveCamp(uid, camp);
      await repository.saveStockEntry(
        uid,
        farmId,
        campId,
        StockEntry(
          id: 'impala',
          campId: campId,
          speciesName: 'Impala',
          count: 5,
          avgWeightKg: 55,
        ),
      );
      await repository.savePlantedArea(
        uid,
        farmId,
        campId,
        PlantedArea(
          id: 'planted',
          campId: campId,
          feedType: PlantedArea.feedTypeTeff,
          areaHa: 2,
          haPerLsu: 1.5,
        ),
      );
      await repository.savePredatorEntry(
        uid,
        farmId,
        campId,
        PredatorEntry(
          id: 'jackal',
          campId: campId,
          predatorName: 'Black-backed Jackal',
          count: 3,
          dailyIntakeKg: 1.0,
        ),
      );

      expect((await repository.getCamps(uid, farmId)).length, 1);

      await repository.deleteStockEntry(uid, farmId, campId, 'impala');
      await repository.deletePlantedArea(uid, farmId, campId, 'planted');
      await repository.deletePredatorEntry(uid, farmId, campId, 'jackal');
      await repository.deleteCamp(uid, farmId, campId);

      expect(await repository.getCamp(uid, farmId, campId), isNull);
      expect(await repository.getStockEntries(uid, farmId, campId), isEmpty);
      expect(await repository.getPlantedAreas(uid, farmId, campId), isEmpty);
      expect(await repository.getPredators(uid, farmId, campId), isEmpty);
    });

    test('every new read and delete is owner-scoped', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = repo(firestore);

      await expectLater(
        repository.getPlantedAreas('someone-else', farmId, campId),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
      await expectLater(
        repository.getPredators('someone-else', farmId, campId),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
      await expectLater(
        repository.deleteCamp('someone-else', farmId, campId),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
      await expectLater(
        repository.deleteStockEntry('someone-else', farmId, campId, 'impala'),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });

  // ── 8. Flag gating: Phase 3 UI is only reachable through the gate ─────
  group('flag gating', () {
    test('the entry point stays behind VeldCarryGate', () {
      final panel = _read(
        'lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart',
      );
      expect(panel.contains('VeldCarryGate('), isTrue);
      expect(panel.contains('VeldCarryCampListScreen('), isTrue);

      // The camp list routes into the detail screen and reads planted areas,
      // so the usage figure reflects real data.
      final list =
          _read('lib/features/veld_carry/ui/veld_carry_camp_list_screen.dart');
      expect(list.contains('VeldCarryCampDetailScreen('), isTrue);
      expect(list.contains('getPlantedAreas('), isTrue);
    });
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
