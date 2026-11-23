import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/pdf_document_engine.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/models/veld_alert.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_alerts.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_report.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 7B contract tests — alerts + veld report / PDF export.
///
/// No real Firebase: the alert rules and the report maths are pure functions,
/// and the repository paths run against `FakeFirebaseFirestore` through the
/// repository's `forTesting` seam.
void main() {
  // The PDF engine loads the branded logo through `rootBundle`, which needs the
  // Flutter test binding before the asset bundle can be read.
  TestWidgetsFlutterBinding.ensureInitialized();

  const uid = 'outfitter-1';
  const farmId = 'farm-1';

  /// Fixed reference day so day-count copy is deterministic.
  final now = DateTime(2026, 11, 23, 10, 30);

  Camp camp({
    String id = 'camp-a',
    String name = 'North Camp',
    double sizeHa = 1000,
    double deptNorm = 10,
    String condition = Camp.veldConditionGood,
    double? lat,
    double? lng,
  }) =>
      Camp(
        id: id,
        farmId: farmId,
        name: name,
        totalSizeHa: sizeHa,
        province: 'Limpopo',
        district: 'Waterberg',
        lat: lat,
        lng: lng,
        veldType: 'Mixed bushveld',
        veldCondition: condition,
        deptNormHaPerLsu: deptNorm,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  /// A counted species row whose LSU is exactly [lsu] per animal.
  StockEntry stock({
    required String campId,
    required int count,
    double lsu = 1.0,
    String speciesName = 'Greater Kudu',
    double avgWeightKg = 200,
  }) =>
      StockEntry(
        id: '$campId-${speciesName.toLowerCase()}',
        campId: campId,
        speciesName: speciesName,
        count: count,
        avgWeightKg: avgWeightKg,
        lsuPerAnimal: lsu,
        guPerAnimal: lsu,
        buPerAnimal: lsu,
      );

  FarmPermit permit({
    String id = 'permit-1',
    String type = FarmPermit.permitTypeCae,
    DateTime? expiry,
    List<String> campIds = const <String>[],
    String number = 'ABC12345',
    String? fileUrl,
    String? status,
  }) =>
      FarmPermit(
        id: id,
        farmId: farmId,
        permitType: type,
        permitNumber: number,
        issuingAuthority: 'Limpopo Nature Conservation',
        province: 'Limpopo',
        expiryDate: expiry,
        campIds: campIds,
        fileUrl: fileUrl,
        status: status,
      );

  RainfallEntry rain({
    required String month,
    double mm = 40,
    String campId = 'camp-a',
  }) =>
      RainfallEntry(
        id: month,
        farmId: farmId,
        campId: campId,
        month: month,
        rainfallMm: mm,
      );

  List<VeldAlert> alertsFor({
    required List<Camp> camps,
    Map<String, List<StockEntry>> stockByCamp = const {},
    List<FarmPermit> permits = const [],
    Map<String, List<RainfallEntry>> rainfallByCamp = const {},
  }) =>
      buildAlerts(
        camps: camps,
        stockByCamp: stockByCamp,
        permits: permits,
        rainfallByCamp: rainfallByCamp,
        now: now,
      );

  group('alerts — stocking pressure', () {
    test('usage over 100% raises a critical overstocked alert', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 110)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      );

      expect(alerts, hasLength(1));
      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typeOverstocked);
      expect(alert.severity, VeldAlert.severityCritical);
      expect(alert.message, 'Camp North Camp is overstocked (110.0%)');
      expect(alert.campId, 'camp-a');
      expect(alert.isFarmWide, isFalse);
    });

    test('usage of exactly 100% is optimal — no alert', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 100)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      );

      expect(alerts, isEmpty);
    });

    test('usage above 120% is severely overstocked', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 130)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      );

      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typeSeverelyOverstocked);
      expect(alert.severity, VeldAlert.severityCritical);
      expect(alert.message, 'Camp North Camp is severely overstocked (130.0%)');
    });

    test('usage of exactly 120% is overstocked, not severe', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 120)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      );

      expect(alerts.single.alertType, VeldAlert.typeOverstocked);
    });
  });

  group('alerts — permits', () {
    test('a permit expiring in 29 days is a warning', () {
      final alerts = alertsFor(
        camps: const [],
        permits: [permit(expiry: DateTime(2026, 12, 22))],
      );

      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typePermitExpiring);
      expect(alert.severity, VeldAlert.severityWarning);
      expect(
        alert.message,
        'Permit CAE (adequate enclosure) expires in 29 days',
      );
      expect(alert.isFarmWide, isTrue);
    });

    test('a permit expiring in 31 days raises nothing', () {
      final alerts = alertsFor(
        camps: const [],
        permits: [permit(expiry: DateTime(2026, 12, 24))],
      );

      expect(alerts, isEmpty);
    });

    test('an expired permit is critical and names the expiry date', () {
      final alerts = alertsFor(
        camps: const [],
        permits: [permit(expiry: DateTime(2026, 11, 1))],
      );

      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typePermitExpired);
      expect(alert.severity, VeldAlert.severityCritical);
      expect(
        alert.message,
        'Permit CAE (adequate enclosure) expired on 2026-11-01',
      );
    });

    test('a permit tied to one camp reports that camp, else farm-wide', () {
      final tied = alertsFor(
        camps: const [],
        permits: [
          permit(expiry: DateTime(2026, 11, 1), campIds: const ['camp-a']),
        ],
      );
      expect(tied.single.campId, 'camp-a');

      final multiple = alertsFor(
        camps: const [],
        permits: [
          permit(
            expiry: DateTime(2026, 11, 1),
            campIds: const ['camp-a', 'camp-b'],
          ),
        ],
      );
      expect(multiple.single.isFarmWide, isTrue);
    });
  });

  group('alerts — housekeeping info', () {
    test('a camp with no stock entries raises the info alert', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: const {'camp-a': <StockEntry>[]},
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      );

      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typeNoStockRecorded);
      expect(alert.severity, VeldAlert.severityInfo);
      expect(alert.message, 'Camp North Camp has no stock recorded yet');
    });

    test('no rainfall in the last 12 months raises the info alert', () {
      final alerts = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 10)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2025-01')],
        },
      );

      final alert = alerts.single;
      expect(alert.alertType, VeldAlert.typeNoRainfallRecorded);
      expect(
        alert.message,
        'Camp North Camp has no rainfall recorded in last 12 months',
      );

      final withRecent = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 10)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11'), rain(month: '2025-01')],
        },
      );
      expect(withRecent, isEmpty);
    });

    test('an unloaded child map is "unknown" and raises nothing', () {
      final alerts = alertsFor(camps: [camp()]);

      expect(alerts, isEmpty);
    });
  });

  group('alerts — ordering + badge count', () {
    test('alerts are sorted critical first, then warning, then info', () {
      final alerts = alertsFor(
        camps: [
          camp(),
          camp(id: 'camp-b', name: 'South Camp'),
        ],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 130)],
          'camp-b': const <StockEntry>[],
        },
        permits: [permit(expiry: DateTime(2026, 12, 22))],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
          'camp-b': [rain(month: '2026-11', campId: 'camp-b')],
        },
      );

      expect(
        alerts.map((a) => a.severity).toList(),
        [
          VeldAlert.severityCritical,
          VeldAlert.severityWarning,
          VeldAlert.severityInfo,
        ],
      );
    });

    test('the badge counts critical + warning only', () {
      final alerts = alertsFor(
        camps: [
          camp(),
          camp(id: 'camp-b', name: 'South Camp'),
        ],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 130)],
          'camp-b': const <StockEntry>[],
        },
        permits: [permit(expiry: DateTime(2026, 12, 22))],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
          'camp-b': [rain(month: '2026-11', campId: 'camp-b')],
        },
      );

      expect(alerts, hasLength(3));
      expect(criticalAndWarningCount(alerts), 2);
    });

    test('an alert serialises round-trip for the session store', () {
      final alert = alertsFor(
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 110)],
        },
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
      ).single;

      final restored = VeldAlert.fromMap(alert.toMap());
      expect(restored, alert);
      expect(restored.isDismissed, isFalse);
      expect(restored.copyWith(isDismissed: true).isDismissed, isTrue);
    });
  });

  group('veld report', () {
    test('totals aggregate capacity, stock, usage and headroom', () {
      final report = buildVeldReport(
        farm: const Farm(id: farmId, name: 'Bosveld Ranch'),
        camps: [
          camp(),
          camp(id: 'camp-b', name: 'South Camp', sizeHa: 500),
        ],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 50)],
          'camp-b': [stock(campId: 'camp-b', count: 25)],
        },
        plantedByCamp: const {},
        predatorsByCamp: const {},
        permits: const [],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11', mm: 25)],
          'camp-b': [rain(month: '2026-11', mm: 20, campId: 'camp-b')],
        },
        now: now,
      );

      expect(report.farmName, 'Bosveld Ranch');
      expect(report.camps, hasLength(2));
      expect(report.totals.campCount, 2);
      expect(report.totals.totalSizeHa, 1500);
      expect(report.totals.veldCapacityLsu, 150);
      expect(report.totals.stockLsu, 75);
      expect(report.totals.usagePct, 50);
      expect(report.totals.headroomLsu, 75);
      expect(report.totals.stockingStatus, stockingUnderstocked);

      // Per-camp rainfall is the trailing 12-month total.
      expect(report.camps.first.rainfallLast12MonthsMm, 25);
      expect(report.camps.last.rainfallLast12MonthsMm, 20);
    });

    test('planted areas add capacity and are listed', () {
      final report = buildVeldReport(
        farm: const Farm(id: farmId, name: 'Bosveld Ranch'),
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 55)],
        },
        plantedByCamp: {
          'camp-a': [
            PlantedArea(
              id: 'area-1',
              campId: 'camp-a',
              feedType: PlantedArea.feedTypeLucerneIrrigated,
              areaHa: 20,
              haPerLsu: 2,
              season: PlantedArea.seasonAllYear,
            ),
          ],
        },
        predatorsByCamp: {
          'camp-a': [
            PredatorEntry(
              id: 'pred-1',
              campId: 'camp-a',
              predatorName: 'Leopard',
              count: 2,
              dailyIntakeKg: 5,
            ),
          ],
        },
        permits: const [],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
        now: now,
      );

      final row = report.camps.single;
      expect(row.veldCapacityLsu, 100);
      expect(row.plantedCapacityLsu, 10);
      expect(row.totalCapacityLsu, 110);
      expect(row.usagePct, 50);
      expect(row.planted.single.label, 'Lucerne irrigated');
      expect(row.planted.single.capacityLsu, 10);
      expect(row.predators.single.predatorName, 'Leopard');
      expect(row.predators.single.count, 2);
      expect(row.species.single.count, 55);
      expect(report.totals.plantedCapacityLsu, 10);
    });

    test('the report carries the generated header line', () {
      final report = buildVeldReport(
        farm: const Farm(id: farmId, name: 'Bosveld Ranch'),
        camps: const [],
        stockByCamp: const {},
        plantedByCamp: const {},
        predatorsByCamp: const {},
        permits: const [],
        rainfallByCamp: const {},
        now: now,
      );

      final text = report.toPlainText();
      expect(
        text,
        contains('Generated 2026-11-23 — JagSpoor Veld Carrying Capacity'),
      );
      expect(text, contains('JAGSPOOR VELD CARRYING CAPACITY'));
      expect(text, contains('Bosveld Ranch'));
    });

    test('the report never exposes coordinates, permit numbers, URLs or '
        'per-animal weights', () {
      final report = buildVeldReport(
        farm: const Farm(id: farmId, name: 'Bosveld Ranch'),
        camps: [camp(lat: -23.456, lng: 29.123)],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 110, avgWeightKg: 200)],
        },
        plantedByCamp: const {},
        predatorsByCamp: const {},
        permits: [
          permit(
            expiry: DateTime(2027, 6, 30),
            number: 'ABC12345',
            fileUrl: 'https://storage.example/permit.pdf',
            status: FarmPermit.permitStatusValid,
          ),
        ],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
        now: now,
      );

      final text = report.toPlainText();
      expect(text, isNot(contains('23.456')));
      expect(text, isNot(contains('29.123')));
      expect(text, isNot(contains('ABC12345')));
      expect(text, isNot(contains('https://')));
      expect(text, isNot(contains('200.0')));
      expect(text, isNot(contains('kg')));
      // The permit still appears — by type, expiry and status only.
      expect(text, contains('CAE (adequate enclosure) — expires 2027-06-30'));

      // Structurally, the report models cannot carry those fields at all.
      final source = File('lib/features/veld_carry/veld_carry_report.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      for (final banned in [
        'permitNumber',
        'fileUrl',
        'avgWeightKg',
        'dailyIntakeKg',
      ]) {
        expect(source, isNot(contains(banned)), reason: 'banned: $banned');
      }
      expect(RegExp(r'\blat\b').hasMatch(source), isFalse);
      expect(RegExp(r'\blng\b').hasMatch(source), isFalse);
    });

    test('the PDF exporter renders a valid PDF through the shared engine',
        () async {
      final report = buildVeldReport(
        farm: const Farm(id: farmId, name: 'Bosveld Ranch'),
        camps: [camp()],
        stockByCamp: {
          'camp-a': [stock(campId: 'camp-a', count: 110)],
        },
        plantedByCamp: const {},
        predatorsByCamp: const {},
        permits: [permit(expiry: DateTime(2026, 11, 1))],
        rainfallByCamp: {
          'camp-a': [rain(month: '2026-11')],
        },
        now: now,
      );

      final doc = await JagSpoorPdfDocument.create(
        title: 'Veld Carrying Capacity Report',
        documentId: 'VELD-$farmId',
      );
      doc.addPage(
        margin: 28,
        content: VeldReportPdfExporter().buildContent(report),
      );
      final bytes = await doc.saveBytes();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('repository (FakeFirebaseFirestore)', () {
    VeldCarryRepository repo(FakeFirebaseFirestore db) =>
        VeldCarryRepository.forTesting(
          currentUserIdResolver: () => uid,
          firestore: db,
        );

    test('getAlertsForFarm derives alerts from the live records', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      await repository.saveCamp(uid, camp());
      await repository.saveStockEntry(
        uid,
        farmId,
        'camp-a',
        stock(campId: 'camp-a', count: 130),
      );
      await repository.savePermit(
        uid,
        farmId,
        permit(expiry: DateTime(2026, 12, 22)),
      );
      await repository.saveRainfallEntry(uid, rain(month: '2026-11'));

      final alerts = await repository.getAlertsForFarm(uid, farmId, now: now);

      expect(alerts.map((a) => a.alertType), [
        VeldAlert.typeSeverelyOverstocked,
        VeldAlert.typePermitExpiring,
      ]);
      expect(criticalAndWarningCount(alerts), 2);

      // Nothing was persisted: the alert collections stay empty.
      final campChildren = await db
          .collection('users')
          .doc(uid)
          .collection('farms')
          .doc(farmId)
          .collection('veldCamps')
          .doc('camp-a')
          .collection('alerts')
          .get();
      expect(campChildren.docs, isEmpty);
    });

    test('getVeldReportForFarm builds the whole-farm snapshot', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);
      await repository.saveCamp(uid, camp());
      await repository.saveStockEntry(
        uid,
        farmId,
        'camp-a',
        stock(campId: 'camp-a', count: 50),
      );
      await repository.saveRainfallEntry(uid, rain(month: '2026-11'));

      final report = await repository.getVeldReportForFarm(
        uid,
        const Farm(id: farmId, name: 'Bosveld Ranch'),
        now: now,
      );

      expect(report.camps.single.name, 'North Camp');
      expect(report.totals.stockLsu, 50);
      expect(report.totals.totalCapacityLsu, 100);
      expect(report.totals.usagePct, 50);
      expect(report.toPlainText(), contains('North Camp'));
    });

    test('alerts and reports are owner-scoped', () async {
      final db = FakeFirebaseFirestore();
      final repository = repo(db);

      await expectLater(
        repository.getAlertsForFarm('another-outfitter', farmId),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
      await expectLater(
        repository.getVeldReportForFarm(
          'another-outfitter',
          const Farm(id: farmId, name: 'Other'),
        ),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });
}
