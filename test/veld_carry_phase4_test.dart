import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_gate.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_hunter_view_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_permit_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_permits_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 4 contract tests: the outfitter permits vault and the read-only
/// hunter veld view.
///
/// The privacy assertions are the point of this suite: the hunter view must
/// never render GPS coordinates, stock weights, private permits, permit
/// numbers or attached files.
void main() {
  const outfitterUid = 'outfitter-1';
  const farmId = 'farm-1';
  const campId = 'camp-1';

  final theme = ThemeController();

  VeldCarryRepository ownerRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(
        currentUserIdResolver: () => outfitterUid,
        firestore: firestore,
      );

  /// A hunter is NOT the farm's outfitter: no uid resolver, so any ownership
  /// check would throw.
  VeldCarryRepository hunterRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(firestore: firestore);

  Camp buildCamp({
    double lat = -24.123456,
    double lng = 28.654321,
    double totalSizeHa = 1000,
  }) =>
      Camp(
        id: campId,
        farmId: farmId,
        name: 'North Camp',
        totalSizeHa: totalSizeHa,
        province: 'Limpopo',
        district: 'Waterberg',
        nearestTown: 'Lephalale',
        lat: lat,
        lng: lng,
        veldType: 'Sweetveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 10,
      );

  StockEntry kudu({int count = 12}) => StockEntry(
        id: 'greater_kudu',
        campId: campId,
        speciesName: 'Greater Kudu',
        feedingClass: StockEntry.feedingClassBrowser,
        count: count,
        avgWeightKg: 218.5,
        grazerPct: 0.1,
        browserPct: 0.9,
        lsuPerAnimal: lsuPerAnimal(218.5),
        guPerAnimal: guPerAnimal(218.5, 0.1),
        buPerAnimal: buPerAnimal(218.5, 0.9),
      );

  StockEntry baboon({int count = 6}) => StockEntry(
        id: 'chacma_baboon',
        campId: campId,
        speciesName: 'Chacma Baboon',
        feedingClass: StockEntry.feedingClassOmnivore,
        count: count,
        avgWeightKg: 22.0,
        grazerPct: 0.0,
        browserPct: 0.0,
        isCounted: false,
        isOmnivore: true,
      );

  FarmPermit permit({
    required String id,
    required String type,
    required String visibility,
    DateTime? expiryDate,
    String number = 'CAE/2026/9981',
    String authority = 'Limpopo Nature Conservation',
    String? fileName,
  }) =>
      FarmPermit(
        id: id,
        farmId: farmId,
        permitType: type,
        permitNumber: number,
        issuingAuthority: authority,
        province: 'Limpopo',
        expiryDate: expiryDate,
        fileName: fileName,
        visibility: visibility,
        uploadedBy: outfitterUid,
      );

  Widget host(Widget child) =>
      MaterialApp(theme: ThemeData.light(), home: child);

  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(child));
    await tester.pumpAndSettle();
  }

  /// Seeds one camp with a counted kudu, a present-only baboon, an ALL_YEAR
  /// lucerne block and two permits (one hunter-visible, one private).
  Future<void> seedFarm(FakeFirebaseFirestore firestore) async {
    final repo = ownerRepo(firestore);
    await repo.saveCamp(outfitterUid, buildCamp());
    await repo.saveStockEntry(outfitterUid, farmId, campId, kudu());
    await repo.saveStockEntry(outfitterUid, farmId, campId, baboon());
    await repo.savePlantedArea(
      outfitterUid,
      farmId,
      campId,
      PlantedArea(
        id: 'lucerne',
        campId: campId,
        feedType: PlantedArea.feedTypeLucerneIrrigated,
        areaHa: 5,
        haPerLsu: 1,
        season: PlantedArea.seasonAllYear,
      ),
    );
    await repo.savePermit(
      outfitterUid,
      farmId,
      permit(
        id: 'permit-visible',
        type: FarmPermit.permitTypeCae,
        visibility: FarmPermit.visibilityHunterVisible,
        expiryDate: DateTime.now().add(const Duration(days: 400)),
        fileName: 'cae-certificate.pdf',
      ),
    );
    await repo.savePermit(
      outfitterUid,
      farmId,
      permit(
        id: 'permit-private',
        type: FarmPermit.permitTypeCites,
        visibility: FarmPermit.visibilityPrivate,
        number: 'CITES/PRIVATE/42',
        authority: 'Private Authority Board',
        expiryDate: DateTime.now().add(const Duration(days: 400)),
      ),
    );
  }

  // ── 1. Permit status bands (calculator) ───────────────────────────────
  group('permitStatus bands', () {
    test('no expiry date is no_expiry', () {
      expect(permitStatus(null), FarmPermit.permitStatusNoExpiry);
    });

    test('a past date is expired', () {
      expect(
        permitStatus(DateTime.now().subtract(const Duration(days: 1))),
        FarmPermit.permitStatusExpired,
      );
    });

    test('within 30 days is expiring_soon', () {
      expect(
        permitStatus(DateTime.now().add(const Duration(days: 10))),
        FarmPermit.permitStatusExpiringSoon,
      );
    });

    test('beyond 30 days is valid', () {
      expect(
        permitStatus(DateTime.now().add(const Duration(days: 90))),
        FarmPermit.permitStatusValid,
      );
    });

    test('the badge label and colour follow the band', () {
      expect(permitStatusLabel(FarmPermit.permitStatusExpiringSoon),
          'Expiring soon');
      expect(permitStatusColor(FarmPermit.permitStatusExpired),
          const Color(0xFFB71C1C));
      expect(permitStatusColor(FarmPermit.permitStatusExpiringSoon),
          const Color(0xFFB26A00));
      expect(permitStatusLabel(FarmPermit.permitStatusNoExpiry), 'No expiry');
    });
  });

  // ── 2. Hunter-safe repository reads ───────────────────────────────────
  group('hunter-safe repository reads', () {
    test('hunterVisiblePermits keeps only hunter_visible permits', () {
      final permits = [
        permit(
          id: 'a',
          type: FarmPermit.permitTypeCae,
          visibility: FarmPermit.visibilityHunterVisible,
        ),
        permit(
          id: 'b',
          type: FarmPermit.permitTypeCites,
          visibility: FarmPermit.visibilityPrivate,
        ),
      ];
      final visible = VeldCarryRepository.hunterVisiblePermits(permits);
      expect(visible.map((p) => p.id), ['a']);
    });

    test('getPermitsForHunter never returns a private permit', () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      final permits = await hunterRepo(firestore)
          .getPermitsForHunter(farmId, outfitterUid: outfitterUid);

      expect(permits.map((p) => p.id), ['permit-visible']);
      expect(
        permits.any((p) => p.visibility == FarmPermit.visibilityPrivate),
        isFalse,
      );
    });

    test('getCampsForHunter reads without the outfitter ownership check',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      final camps = await hunterRepo(firestore)
          .getCampsForHunter(farmId, outfitterUid: outfitterUid);

      expect(camps, hasLength(1));
      expect(camps.first.name, 'North Camp');
    });

    test('the ownership-gated read still rejects a hunter', () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      expect(
        () => hunterRepo(firestore).getCamps(outfitterUid, farmId),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });

  // ── 3. Present-only species contribute 0 LSU ──────────────────────────
  group('present-only species', () {
    test('a baboon row adds no LSU while the kudu does', () {
      final view = HunterCampVeldView(
        camp: buildCamp(),
        stock: [kudu(count: 12), baboon(count: 6)],
        planted: const [],
      );

      // 12 kudu at ~218.5 kg, 6 baboons at 22 kg — only the kudu counts.
      expect(view.currentStockLsu, closeTo(12 * lsuPerAnimal(218.5), 1e-9));
      expect(view.presentOnlyStock, hasLength(1));
      expect(view.countedStock, hasLength(1));
      expect(view.presentOnlyStock.first.totalLsu, 0.0);
    });

    test('present-only entries are labelled "Present, not counted"', () {
      expect(
        hunterPresentOnlyLabel('Chacma Baboon'),
        'Baboon — Present, not counted',
      );
    });
  });

  // ── 4. Hunter view privacy ────────────────────────────────────────────
  group('hunter view', () {
    testWidgets('renders the hunter-safe camp basics but no GPS coordinates',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await pumpTall(
        tester,
        VeldCarryHunterViewScreen(
          outfitterUid: outfitterUid,
          farmId: farmId,
          farmName: 'Bosveld Ranch',
          theme: theme,
          repository: hunterRepo(firestore),
        ),
      );

      // Hunter-safe facts.
      expect(find.text('Bosveld Ranch'), findsOneWidget);
      expect(find.text('North Camp'), findsOneWidget);
      expect(find.textContaining('1000 ha'), findsOneWidget);
      expect(find.textContaining('Sweetveld'), findsOneWidget);
      expect(find.textContaining('Limpopo · Waterberg'), findsOneWidget);

      // GPS / exact location must never render.
      expect(find.textContaining('-24.12'), findsNothing);
      expect(find.textContaining('28.65'), findsNothing);
      expect(find.textContaining('Lephalale'), findsNothing);
      expect(find.textContaining('lat'), findsNothing);
      expect(find.textContaining('lng'), findsNothing);
    });

    testWidgets('hides weights, permit numbers, authorities, files and the '
        'private permit', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await pumpTall(
        tester,
        VeldCarryHunterViewScreen(
          outfitterUid: outfitterUid,
          farmId: farmId,
          farmName: 'Bosveld Ranch',
          theme: theme,
          repository: hunterRepo(firestore),
        ),
      );

      // Weights stay on the outfitter side.
      expect(find.textContaining('218'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining('GU'), findsNothing);
      expect(find.textContaining('BU'), findsNothing);

      // Permit number / authority / attachment are never shared.
      expect(find.textContaining('CAE/2026/9981'), findsNothing);
      expect(find.textContaining('Limpopo Nature Conservation'), findsNothing);
      expect(find.textContaining('cae-certificate.pdf'), findsNothing);

      // The private permit (and its number) never reaches the hunter.
      expect(find.textContaining('CITES'), findsNothing);
      expect(find.textContaining('CITES/PRIVATE/42'), findsNothing);
      expect(find.textContaining('Private Authority Board'), findsNothing);

      // The hunter-visible permit IS shown, by type only.
      expect(find.textContaining('CAE'), findsWidgets);
    });

    testWidgets('shows counted species with counts and the present-only list',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await pumpTall(
        tester,
        VeldCarryHunterViewScreen(
          outfitterUid: outfitterUid,
          farmId: farmId,
          theme: theme,
          repository: hunterRepo(firestore),
        ),
      );

      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('veldHunterStockCount_camp-1_greater_kudu')),
        findsOneWidget,
      );
      expect(find.text('Baboon — Present, not counted'), findsOneWidget);
      expect(find.text('0 LSU'), findsOneWidget);
    });

    testWidgets('shows the empty-share message when the farm has no camps',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await pumpTall(
        tester,
        VeldCarryHunterViewScreen(
          outfitterUid: outfitterUid,
          farmId: farmId,
          theme: theme,
          repository: hunterRepo(firestore),
        ),
      );

      expect(
        find.text('No veld information shared for this camp yet.'),
        findsOneWidget,
      );
    });

    testWidgets('renders the expiry badge for a shared permit',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);
      await repo.saveCamp(outfitterUid, buildCamp());
      await repo.savePermit(
        outfitterUid,
        farmId,
        permit(
          id: 'permit-soon',
          type: FarmPermit.permitTypeTransport,
          visibility: FarmPermit.visibilityHunterVisible,
          expiryDate: DateTime.now().add(const Duration(days: 5)),
        ),
      );

      await pumpTall(
        tester,
        VeldCarryHunterViewScreen(
          outfitterUid: outfitterUid,
          farmId: farmId,
          theme: theme,
          repository: hunterRepo(firestore),
        ),
      );

      expect(
        find.byKey(const ValueKey('veldHunterPermitStatus_permit-soon')),
        findsOneWidget,
      );
      expect(find.text('Expiring soon'), findsOneWidget);
    });
  });

  // ── 5. The hunter entry tile ──────────────────────────────────────────
  group('hunter entry tile', () {
    testWidgets('renders nothing when the farm has no veld camps',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        host(
          Scaffold(
            body: VeldCarryHunterEntryTile(
              outfitterUid: outfitterUid,
              farmId: farmId,
              theme: theme,
              repository: hunterRepo(firestore),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('veldHunterEntryTile')), findsNothing);
    });

    testWidgets('renders one tile when the farm has a camp', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await tester.pumpWidget(
        host(
          Scaffold(
            body: VeldCarryHunterEntryTile(
              outfitterUid: outfitterUid,
              farmId: farmId,
              theme: theme,
              repository: hunterRepo(firestore),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('veldHunterEntryTile')),
        findsOneWidget,
      );
      expect(find.text('Veld & Carrying Capacity'), findsOneWidget);
    });

    testWidgets('renders nothing at all while the feature flag is OFF',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await tester.pumpWidget(
        host(
          Scaffold(
            body: VeldCarryGate(
              flag: VeldCarryFeatureFlag.forTesting(
                compileTimeEnabled: false,
                adminConfigEnabled: false,
              ),
              builder: (_) => VeldCarryHunterEntryTile(
                outfitterUid: outfitterUid,
                farmId: farmId,
                theme: theme,
                repository: hunterRepo(firestore),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('veldHunterEntryTile')), findsNothing);
      expect(find.text('Veld & Carrying Capacity'), findsNothing);
    });
  });

  // ── 6. Permits vault (outfitter) ──────────────────────────────────────
  group('permits vault', () {
    testWidgets('lists type, number, authority, province, expiry, status and '
        'visibility', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      await pumpTall(
        tester,
        VeldCarryPermitsScreen(
          farmId: farmId,
          farmName: 'Bosveld Ranch',
          theme: theme,
          repository: ownerRepo(firestore),
          currentUidOverride: outfitterUid,
        ),
      );

      expect(find.byKey(const ValueKey('veldPermitCard_permit-visible')),
          findsOneWidget);
      expect(find.textContaining('CAE/2026/9981'), findsOneWidget);
      expect(find.textContaining('Limpopo Nature Conservation'), findsOneWidget);
      // Both permits carry the same province.
      expect(find.text('Limpopo'), findsNWidgets(2));
      expect(find.text('Hunter visible'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byKey(const ValueKey('veldPermitStatus_permit-visible')),
          findsOneWidget);
      // Both permits are listed for the outfitter (private included).
      expect(find.byKey(const ValueKey('veldPermitCard_permit-private')),
          findsOneWidget);
    });

    testWidgets('shows an amber badge for expiring permits and red for expired',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);
      await repo.savePermit(
        outfitterUid,
        farmId,
        permit(
          id: 'permit-soon',
          type: FarmPermit.permitTypeVet,
          visibility: FarmPermit.visibilityPrivate,
          expiryDate: DateTime.now().add(const Duration(days: 7)),
        ),
      );
      await repo.savePermit(
        outfitterUid,
        farmId,
        permit(
          id: 'permit-expired',
          type: FarmPermit.permitTypeTops,
          visibility: FarmPermit.visibilityPrivate,
          expiryDate: DateTime.now().subtract(const Duration(days: 7)),
        ),
      );

      await pumpTall(
        tester,
        VeldCarryPermitsScreen(
          farmId: farmId,
          theme: theme,
          repository: repo,
          currentUidOverride: outfitterUid,
        ),
      );

      expect(find.text('Expiring soon'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('delete asks for confirmation and then removes the permit',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);
      final repo = ownerRepo(firestore);

      await pumpTall(
        tester,
        VeldCarryPermitsScreen(
          farmId: farmId,
          theme: theme,
          repository: repo,
          currentUidOverride: outfitterUid,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('veldPermitDelete_permit-visible')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete CAE'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('DELETE'),
        ),
      );
      await tester.pumpAndSettle();

      final remaining = await repo.getPermits(outfitterUid, farmId);
      expect(remaining.map((p) => p.id), ['permit-private']);
    });
  });

  // ── 7. Permit form ────────────────────────────────────────────────────
  group('permit form', () {
    test('species options are counted species with an authorised weight', () {
      final options = veldCarryPermitSpeciesOptions();
      expect(options, isNotEmpty);
      expect(
        options.every((s) => s.isCounted && s.avgWeightKg > 0),
        isTrue,
      );
      // Present-only species are never attached to a permit.
      expect(
        options.any((s) => s.speciesName == 'Chacma Baboon'),
        isFalse,
      );
    });

    testWidgets('saves a permit private by default with the attachment name',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);

      await pumpTall(
        tester,
        VeldCarryPermitFormScreen(
          farmId: farmId,
          theme: theme,
          repository: repo,
          currentUidOverride: outfitterUid,
          camps: [buildCamp()],
          filePickerOverride: () async => 'cae-certificate.pdf',
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('veldPermitNumberField')),
        'CAE/2027/0001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('veldPermitAuthorityField')),
        'Limpopo Nature Conservation',
      );
      await tester.tap(find.byKey(const ValueKey('veldPermitPickFileButton')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('veldPermitSaveButton')),
      );
      await tester.tap(find.byKey(const ValueKey('veldPermitSaveButton')));
      await tester.pumpAndSettle();

      final saved = await repo.getPermits(outfitterUid, farmId);
      expect(saved, hasLength(1));
      expect(saved.single.permitNumber, 'CAE/2027/0001');
      expect(saved.single.issuingAuthority, 'Limpopo Nature Conservation');
      expect(saved.single.visibility, FarmPermit.visibilityPrivate);
      expect(saved.single.fileName, 'cae-certificate.pdf');
      // No invented Storage URL in this phase.
      expect(saved.single.fileUrl, isNull);
      expect(saved.single.status, FarmPermit.permitStatusNoExpiry);
    });
  });
}
