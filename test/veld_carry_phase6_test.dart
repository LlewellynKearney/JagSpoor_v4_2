import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_permit_form_screen.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 6 contract tests.
///
/// Three concerns, each with its own group:
///
///  1. The hunter PERMITS blocker fix — the read must issue
///     `.where('visibility', isEqualTo: 'hunter_visible')` (Firestore rules are
///     not filters) AND keep the client-side filter as a second gate.
///  2. The booking relationship gate — `hunterHasBookingForFarm` against the
///     app's real `bookings` collection, and the fail-closed hunter reads.
///  3. The permit document upload — path/content-type contracts, the 10 MB +
///     type guards, and the save/abort behaviour.
void main() {
  const outfitterUid = 'outfitter-1';
  const hunterUid = 'hunter-1';
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

  Camp buildCamp() => Camp(
        id: campId,
        farmId: farmId,
        name: 'North Camp',
        totalSizeHa: 1000,
        province: 'Limpopo',
        district: 'Waterberg',
        nearestTown: 'Lephalale',
        veldType: 'Sweetveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 10,
      );

  FarmPermit buildPermit({
    required String id,
    required String visibility,
    String? fileUrl,
  }) =>
      FarmPermit(
        id: id,
        farmId: farmId,
        permitType: FarmPermit.permitTypeCae,
        permitNumber: 'CAE/$id',
        issuingAuthority: 'Limpopo Nature Conservation',
        province: 'Limpopo',
        visibility: visibility,
        fileUrl: fileUrl,
        fileName: fileUrl == null ? null : 'doc.pdf',
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

  /// Seeds a camp with a counted stock row, a planted block, one
  /// hunter-visible permit and two private permits.
  Future<void> seedFarm(FakeFirebaseFirestore firestore) async {
    final repo = ownerRepo(firestore);
    await repo.saveCamp(outfitterUid, buildCamp());
    await repo.saveStockEntry(
      outfitterUid,
      farmId,
      campId,
      StockEntry(
        id: 'greater_kudu',
        campId: campId,
        speciesName: 'Greater Kudu',
        feedingClass: StockEntry.feedingClassBrowser,
        count: 12,
        avgWeightKg: 218.5,
        grazerPct: 0.1,
        browserPct: 0.9,
      ),
    );
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
      buildPermit(
        id: 'permit-visible',
        visibility: FarmPermit.visibilityHunterVisible,
      ),
    );
    await repo.savePermit(
      outfitterUid,
      farmId,
      buildPermit(
        id: 'permit-private-a',
        visibility: FarmPermit.visibilityPrivate,
      ),
    );
    await repo.savePermit(
      outfitterUid,
      farmId,
      buildPermit(
        id: 'permit-private-b',
        visibility: FarmPermit.visibilityPrivate,
      ),
    );
  }

  /// Writes one booking straight into the app's real `bookings` collection.
  Future<void> seedBooking(
    FakeFirebaseFirestore firestore, {
    String id = 'booking-1',
    String bookingHunter = hunterUid,
    String bookingFarm = farmId,
    String status = BookingStatus.confirmed,
  }) async {
    await firestore.collection('bookings').doc(id).set({
      'hunterId': bookingHunter,
      'outfitterId': outfitterUid,
      'farmId': bookingFarm,
      'status': status,
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // 1. THE BLOCKER — hunter permits query must constrain `visibility`
  // ══════════════════════════════════════════════════════════════════════
  group('hunter permits query (go-live blocker)', () {
    test('returns ONLY hunter_visible permits from a mixed collection',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      // The query is:
      //   users/{uid}/farms/{farmId}/permits
      //     .where('visibility', isEqualTo: 'hunter_visible')
      //     .get()
      final permits = await hunterRepo(firestore)
          .getPermitsForHunter(farmId, outfitterUid: outfitterUid);

      expect(permits.map((p) => p.id), ['permit-visible']);
      expect(
        permits.any((p) => p.visibility == FarmPermit.visibilityPrivate),
        isFalse,
      );
    });

    test('a private-only farm yields an empty list (query is constrained)',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);
      await repo.savePermit(
        outfitterUid,
        farmId,
        buildPermit(
          id: 'only-private',
          visibility: FarmPermit.visibilityPrivate,
        ),
      );

      final permits = await hunterRepo(firestore)
          .getPermitsForHunter(farmId, outfitterUid: outfitterUid);

      expect(permits, isEmpty);
    });

    test('hunterVisiblePermits stays the second gate (defence in depth)', () {
      final mixed = [
        buildPermit(
          id: 'v',
          visibility: FarmPermit.visibilityHunterVisible,
        ),
        buildPermit(id: 'p', visibility: FarmPermit.visibilityPrivate),
      ];

      expect(
        VeldCarryRepository.hunterVisiblePermits(mixed).map((p) => p.id),
        ['v'],
      );
      // A mis-set document can never pass the Dart gate either.
      expect(VeldCarryRepository.hunterVisiblePermits(const []), isEmpty);
    });

    test('the repository source issues the visibility where() AND the '
        'client-side filter', () {
      final source =
          File('lib/features/veld_carry/veld_carry_repository.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');

      // The Firestore query constraint — without it a non-owner read is
      // rejected with permission-denied under the go-live rule.
      expect(
        source.contains(
          ".where('visibility', isEqualTo: "
          "FarmPermit.visibilityHunterVisible)",
        ),
        isTrue,
        reason: 'getPermitsForHunter must constrain visibility in the query',
      );
      // ... and the client-side filter must survive it.
      expect(source.contains('return hunterVisiblePermits(permits);'), isTrue);

      // Ordering: the where() must precede the get() inside the method.
      final methodStart = source.indexOf('getPermitsForHunter(');
      expect(methodStart, greaterThan(0));
      final body = source.substring(methodStart, methodStart + 1800);
      final whereAt = body.indexOf(".where('visibility'");
      final getAt = body.indexOf('.get();');
      expect(whereAt, greaterThan(0));
      expect(getAt, greaterThan(whereAt));
    });

    test('camps / stock / plantedAreas rules carry NO per-document condition',
        () {
      final rules =
          File('firestore.rules.veld_carry.GO_LIVE_READY').readAsStringSync();

      for (final path in const [
        'veldCamps/{campId} {',
        '/stock/{entryId} {',
        '/plantedAreas/{areaId} {',
      ]) {
        final start = rules.indexOf(path);
        expect(start, greaterThan(0), reason: 'missing block: $path');
        final block = rules.substring(start, start + 900);
        // Their read grant is the plain signed-in check — no `resource.data`
        // inspection — so an unconstrained query is valid for them. (A
        // negative lookbehind keeps `request.resource.data` — the payload
        // guard on create/update — from counting as a READ condition.)
        expect(block.contains('allow read: if isSignedIn();'), isTrue,
            reason: '$path should keep the plain signed-in read');
        expect(
          RegExp(r'(?<!request\.)resource\.data').hasMatch(block),
          isFalse,
          reason: '$path must not have a per-document read condition',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2. BOOKING GATE
  // ══════════════════════════════════════════════════════════════════════
  group('hunterHasBookingForFarm', () {
    test('true for a Confirmed booking on the farm', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore);

      expect(
        await hunterRepo(firestore)
            .hunterHasBookingForFarm(hunterUid, farmId),
        isTrue,
      );
    });

    test('true for a Completed booking', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore, status: BookingStatus.completed);

      expect(
        await hunterRepo(firestore)
            .hunterHasBookingForFarm(hunterUid, farmId),
        isTrue,
      );
    });

    test('true for the legacy "Paid" status', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore, status: 'Paid');

      expect(
        await hunterRepo(firestore)
            .hunterHasBookingForFarm(hunterUid, farmId),
        isTrue,
      );
    });

    test('false for pending / awaiting-payment / declined / cancelled',
        () async {
      for (final status in const [
        BookingStatus.pendingApproval,
        BookingStatus.approvedAwaitingPayment,
        BookingStatus.declined,
        BookingStatus.cancelled,
      ]) {
        final firestore = FakeFirebaseFirestore();
        await seedBooking(firestore, status: status);

        expect(
          await hunterRepo(firestore)
              .hunterHasBookingForFarm(hunterUid, farmId),
          isFalse,
          reason: 'status "$status" must not grant veld access',
        );
      }
    });

    test('false when the booking is on a different farm', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore, bookingFarm: 'another-farm');

      expect(
        await hunterRepo(firestore)
            .hunterHasBookingForFarm(hunterUid, farmId),
        isFalse,
      );
    });

    test('false when the booking belongs to another hunter', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore, bookingHunter: 'someone-else');

      expect(
        await hunterRepo(firestore)
            .hunterHasBookingForFarm(hunterUid, farmId),
        isFalse,
      );
    });

    test('false for a blank uid or farm id', () async {
      final firestore = FakeFirebaseFirestore();
      await seedBooking(firestore);
      final repo = hunterRepo(firestore);

      expect(await repo.hunterHasBookingForFarm('', farmId), isFalse);
      expect(await repo.hunterHasBookingForFarm(hunterUid, '  '), isFalse);
    });

    test('fails CLOSED when Firestore is unavailable', () async {
      // No injected Firestore and no Firebase app -> _requireFirestore throws;
      // the gate must swallow it and deny.
      final repo = VeldCarryRepository.forTesting();
      expect(
        await repo.hunterHasBookingForFarm(hunterUid, farmId),
        isFalse,
      );
    });

    test('hunter reads return nothing without a booking (fail closed)',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);
      final repo = hunterRepo(firestore);

      expect(
        await repo.getCampsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isEmpty,
      );
      expect(
        await repo.getCampForHunter(
          farmId,
          campId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isNull,
      );
      expect(
        await repo.getStockForHunter(
          farmId,
          campId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isEmpty,
      );
      expect(
        await repo.getPlantedAreasForHunter(
          farmId,
          campId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isEmpty,
      );
      expect(
        await repo.getPermitsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        isEmpty,
      );
    });

    test('hunter reads return data once a Confirmed booking exists', () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);
      await seedBooking(firestore);
      final repo = hunterRepo(firestore);

      expect(
        await repo.getCampsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        hasLength(1),
      );
      expect(
        await repo.getStockForHunter(
          farmId,
          campId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        hasLength(1),
      );
      expect(
        await repo.getPlantedAreasForHunter(
          farmId,
          campId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        hasLength(1),
      );
      expect(
        await repo.getPermitsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: hunterUid,
        ),
        hasLength(1),
      );
    });

    test('omitting hunterUid keeps the pre-Phase-6 behaviour', () async {
      final firestore = FakeFirebaseFirestore();
      await seedFarm(firestore);

      // No gate requested -> the read proceeds (outfitter-side / legacy use).
      expect(
        await hunterRepo(firestore)
            .getCampsForHunter(farmId, outfitterUid: outfitterUid),
        hasLength(1),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 3. PERMIT DOCUMENT UPLOAD
  // ══════════════════════════════════════════════════════════════════════
  group('permit document upload', () {
    test('storage path is veld_permits/{uid}/{farm}/{permit}/{file}', () {
      expect(
        VeldCarryPermitFormScreen.permitStoragePath(
          outfitterUid: outfitterUid,
          farmId: farmId,
          permitId: 'permit-1',
          fileName: 'cae-certificate.pdf',
        ),
        'veld_permits/outfitter-1/farm-1/permit-1/cae-certificate.pdf',
      );
    });

    test('storage path cannot be escaped by a crafted file name', () {
      final path = VeldCarryPermitFormScreen.permitStoragePath(
        outfitterUid: outfitterUid,
        farmId: farmId,
        permitId: 'permit-1',
        fileName: '../../other/secret.pdf',
      );

      expect(path, startsWith('veld_permits/outfitter-1/farm-1/permit-1/'));
      expect(path.contains('../'), isFalse);
    });

    test('content type is derived from the extension', () {
      expect(
        VeldCarryPermitFormScreen.contentTypeForExtension('pdf'),
        'application/pdf',
      );
      expect(
        VeldCarryPermitFormScreen.contentTypeForExtension('JPG'),
        'image/jpeg',
      );
      expect(
        VeldCarryPermitFormScreen.contentTypeForExtension('png'),
        'image/png',
      );
      expect(
        VeldCarryPermitFormScreen.contentTypeForExtension('docx'),
        'application/octet-stream',
      );
    });

    test('PickedPermitFile reports a lower-cased extension', () {
      const picked = PickedPermitFile(
        name: 'Permit.PDF',
        path: '/tmp/Permit.PDF',
        sizeBytes: 1024,
      );
      expect(picked.extension, 'pdf');
      expect(
        const PickedPermitFile(name: 'noext', path: '/tmp/x', sizeBytes: 1)
            .extension,
        '',
      );
    });

    testWidgets('a file over 10 MB is rejected before any upload',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await pumpTall(
        tester,
        VeldCarryPermitFormScreen(
          farmId: farmId,
          theme: theme,
          repository: ownerRepo(firestore),
          currentUidOverride: outfitterUid,
          filePickerOverride: () async => PickedPermitFile(
            name: 'huge.pdf',
            path: '/tmp/huge.pdf',
            sizeBytes: VeldCarryPermitFormScreen.maxPermitFileBytes + 1,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('veldPermitPickFileButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('too large'), findsOneWidget);
      // Nothing staged: the button still shows the placeholder.
      expect(find.text('Choose file'), findsOneWidget);
    });

    testWidgets('a non-PDF / non-image file is rejected', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await pumpTall(
        tester,
        VeldCarryPermitFormScreen(
          farmId: farmId,
          theme: theme,
          repository: ownerRepo(firestore),
          currentUidOverride: outfitterUid,
          filePickerOverride: () async => const PickedPermitFile(
            name: 'notes.docx',
            path: '/tmp/notes.docx',
            sizeBytes: 2048,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('veldPermitPickFileButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unsupported file type'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
    });

    testWidgets('save uploads the document and persists fileUrl + fileName',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);
      String? capturedPath;
      String? capturedType;

      await pumpTall(
        tester,
        VeldCarryPermitFormScreen(
          farmId: farmId,
          theme: theme,
          repository: repo,
          currentUidOverride: outfitterUid,
          filePickerOverride: () async => const PickedPermitFile(
            name: 'cae-certificate.pdf',
            path: '/tmp/cae-certificate.pdf',
            sizeBytes: 4096,
          ),
          uploadOverride: ({
            required File file,
            required String storagePath,
            required String contentType,
            void Function(double progress)? onProgress,
          }) async {
            capturedPath = storagePath;
            capturedType = contentType;
            onProgress?.call(0.5);
            return 'https://storage.example/veld_permits/cae.pdf';
          },
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
      expect(saved.single.fileName, 'cae-certificate.pdf');
      expect(
        saved.single.fileUrl,
        'https://storage.example/veld_permits/cae.pdf',
      );
      expect(capturedPath, contains('veld_permits/outfitter-1/farm-1/'));
      expect(capturedPath, endsWith('cae-certificate.pdf'));
      expect(capturedType, 'application/pdf');
    });

    testWidgets('a failed upload aborts the save with an error', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ownerRepo(firestore);

      await pumpTall(
        tester,
        VeldCarryPermitFormScreen(
          farmId: farmId,
          theme: theme,
          repository: repo,
          currentUidOverride: outfitterUid,
          filePickerOverride: () async => const PickedPermitFile(
            name: 'cae-certificate.pdf',
            path: '/tmp/cae-certificate.pdf',
            sizeBytes: 4096,
          ),
          uploadOverride: ({
            required File file,
            required String storagePath,
            required String contentType,
            void Function(double progress)? onProgress,
          }) async {
            throw Exception('storage offline');
          },
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('veldPermitNumberField')),
        'CAE/2027/0002',
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

      expect(find.textContaining('Could not upload the attachment'),
          findsOneWidget);
      // The permit must NOT be written pointing at a missing file.
      expect(await repo.getPermits(outfitterUid, farmId), isEmpty);
    });

    test('the hunter view never references the file URL or name', () {
      final source =
          File('lib/features/veld_carry/ui/veld_carry_hunter_view_screen.dart')
              .readAsStringSync();

      expect(source.contains('fileUrl'), isFalse);
      expect(source.contains('fileName'), isFalse);
    });
  });
}
