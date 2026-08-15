// Shot Group Target Analyzer — target session logging tests.
//
// Covers the TargetSessionLog model round-trip + the pure buildLog helper,
// and an integration test of TargetSessionLogManager.saveSession/loadSessions
// against a REAL in-memory SQLite database (sqflite_common_ffi) — no mocks of
// the manager itself.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/target_session_log.dart';
import 'package:jagspoor/features/hunter_mode/services/shot_group_analyzer_service.dart';
import 'package:jagspoor/features/hunter_mode/services/target_session_log_manager.dart';
import 'package:jagspoor/features/shared/data/services/local_database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final svc = ShotGroupAnalyzerService.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // LocalDatabaseService opens a fixed `jagspoor.db` under the databases
    // path; delete it before each test so table state never bleeds between
    // tests, then reset the cached handle so the next access re-creates it.
    final tempDir = await databaseFactory.getDatabasesPath();
    final prodDbPath = p.join(tempDir, 'jagspoor.db');
    await databaseFactory.deleteDatabase(prodDbPath);
    LocalDatabaseService.resetForTest();
  });

  group('TargetSessionLog model', () {
    test('toMap / fromMap round-trips every field', () {
      final log = TargetSessionLog(
        id: 'tsl_1',
        firearmId: 'rifle_42',
        firearmLabel: 'Tikka T3x (.308 Win)',
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        shotCount: 5,
        extremeSpreadMm: 31.2,
        extremeSpreadInches: 1.228,
        extremeSpreadAngular: 1.17,
        meanRadiusMm: 9.4,
        meanRadiusAngular: 0.35,
        offsetHorizontalMm: 5.0,
        offsetVerticalMm: -3.0,
        suggestedUpClicks: 3,
        suggestedRightClicks: -2,
        precisionCategory: '1 MOA Group',
        calibrated: true,
        aimPoint: const Offset(120, 80),
        createdAt: '2026-08-15T10:00:00.000Z',
      );
      final restored = TargetSessionLog.fromMap(log.toMap());
      expect(restored.id, 'tsl_1');
      expect(restored.firearmId, 'rifle_42');
      expect(restored.firearmLabel, 'Tikka T3x (.308 Win)');
      expect(restored.distance, 100);
      expect(restored.distanceUnit, DistanceUnit.yards);
      expect(restored.angularUnit, AngularUnit.moa);
      expect(restored.clickValue, 0.25);
      expect(restored.shotCount, 5);
      expect(restored.extremeSpreadMm, 31.2);
      expect(restored.extremeSpreadInches, 1.228);
      expect(restored.extremeSpreadAngular, 1.17);
      expect(restored.meanRadiusMm, 9.4);
      expect(restored.meanRadiusAngular, 0.35);
      expect(restored.offsetHorizontalMm, 5.0);
      expect(restored.offsetVerticalMm, -3.0);
      expect(restored.suggestedUpClicks, 3);
      expect(restored.suggestedRightClicks, -2);
      expect(restored.precisionCategory, '1 MOA Group');
      expect(restored.calibrated, isTrue);
      expect(restored.aimPoint, const Offset(120, 80));
      expect(restored.createdAt, '2026-08-15T10:00:00.000Z');
    });

    test('fromMap tolerates missing aim point (null columns)', () {
      final restored = TargetSessionLog.fromMap(const {
        'id': 'tsl_2',
        'firearmId': '',
        'firearmLabel': 'Unlinked',
        'distance': 50,
        'distanceUnit': 'meters',
        'angularUnit': 'MIL',
        'clickValue': 0.1,
        'shotCount': 3,
        'extremeSpreadMm': 0.0,
        'extremeSpreadInches': 0.0,
        'extremeSpreadAngular': 0.0,
        'meanRadiusMm': 0.0,
        'meanRadiusAngular': 0.0,
        'offsetHorizontalMm': 0.0,
        'offsetVerticalMm': 0.0,
        'suggestedUpClicks': 0,
        'suggestedRightClicks': 0,
        'precisionCategory': 'Open Group',
        'calibrated': 0,
        // aimPointDx / aimPointDy absent
        'createdAt': '2026-08-15T11:00:00.000Z',
      });
      expect(restored.aimPoint, isNull);
      expect(restored.calibrated, isFalse);
      expect(restored.distanceUnit, DistanceUnit.meters);
      expect(restored.angularUnit, AngularUnit.mil);
    });

    test('unit labels map to the storage strings', () {
      final yards = TargetSessionLog(
        id: 'a',
        firearmId: '',
        firearmLabel: '',
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        shotCount: 0,
        extremeSpreadMm: 0,
        extremeSpreadInches: 0,
        extremeSpreadAngular: 0,
        meanRadiusMm: 0,
        meanRadiusAngular: 0,
        offsetHorizontalMm: 0,
        offsetVerticalMm: 0,
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
        precisionCategory: '',
        calibrated: false,
        aimPoint: null,
        createdAt: '',
      );
      expect(yards.distanceUnitLabel, 'yards');
      expect(yards.angularUnitLabel, 'MOA');

      final meters = TargetSessionLog(
        id: 'b',
        firearmId: '',
        firearmLabel: '',
        distance: 100,
        distanceUnit: DistanceUnit.meters,
        angularUnit: AngularUnit.mil,
        clickValue: 0.1,
        shotCount: 0,
        extremeSpreadMm: 0,
        extremeSpreadInches: 0,
        extremeSpreadAngular: 0,
        meanRadiusMm: 0,
        meanRadiusAngular: 0,
        offsetHorizontalMm: 0,
        offsetVerticalMm: 0,
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
        precisionCategory: '',
        calibrated: false,
        aimPoint: null,
        createdAt: '',
      );
      expect(meters.distanceUnitLabel, 'meters');
      expect(meters.angularUnitLabel, 'MIL');
    });
  });

  group('TargetSessionLogManager.buildLog (pure)', () {
    test('captures the analysis geometry + screen inputs', () {
      final shots = [
        ShotImpact(pixel: const Offset(0, 0)),
        ShotImpact(pixel: const Offset(40, 0)),
        ShotImpact(pixel: const Offset(0, 30)),
      ];
      final analysis = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        aimPoint: const Offset(20, 10),
        angularUnit: AngularUnit.moa,
      );
      final log = TargetSessionLogManager.buildLog(
        id: 'tsl_pure',
        createdAt: '2026-08-15T12:00:00.000Z',
        analysis: analysis,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        firearmId: 'rifle_1',
        firearmLabel: 'Rem 700 (.308)',
        suggestedUpClicks: 4,
        suggestedRightClicks: -1,
      );
      expect(log.id, 'tsl_pure');
      expect(log.shotCount, 3);
      expect(log.firearmId, 'rifle_1');
      expect(log.firearmLabel, 'Rem 700 (.308)');
      expect(log.calibrated, isTrue);
      expect(log.extremeSpreadMm, closeTo(50.0, 1e-6));
      expect(log.aimPoint, const Offset(20, 10));
      expect(log.suggestedUpClicks, 4);
      expect(log.suggestedRightClicks, -1);
      expect(log.precisionCategory, isNotEmpty);
    });
  });

  group('TargetSessionLogManager SQLite integration', () {
    test('saveSession persists a row and loadSessions reads it back', () async {
      final shots = [
        ShotImpact(pixel: const Offset(0, 0)),
        ShotImpact(pixel: const Offset(30, 0)),
      ];
      final analysis = svc.analyze(
        shots: shots,
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
      );

      final id = await TargetSessionLogManager.instance.saveSession(
        analysis: analysis,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        firearmId: 'rifle_x',
        firearmLabel: 'Tikka T3x (.308 Win)',
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
      );
      expect(id, isNotNull);

      final sessions = await TargetSessionLogManager.instance.loadSessions();
      expect(sessions.length, 1);
      expect(sessions.first.id, id);
      expect(sessions.first.firearmId, 'rifle_x');
      expect(sessions.first.firearmLabel, 'Tikka T3x (.308 Win)');
      expect(sessions.first.shotCount, 2);
      expect(sessions.first.calibrated, isTrue);
      expect(sessions.first.extremeSpreadMm, closeTo(30.0, 1e-6));
      expect(sessions.first.distanceUnit, DistanceUnit.yards);
      expect(sessions.first.angularUnit, AngularUnit.moa);
    });

    test('sessions are returned newest-first', () async {
      final makeAnalysis = () => svc.analyze(
            shots: [ShotImpact(pixel: const Offset(0, 0))],
            pxPerMm: 1.0,
            distance: 100,
            distanceUnit: DistanceUnit.yards,
            angularUnit: AngularUnit.moa,
          );
      await TargetSessionLogManager.instance.saveSession(
        analysis: makeAnalysis(),
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        firearmId: '',
        firearmLabel: 'first',
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
      );
      // Small delay so the second save has a distinct (later) timestamp.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await TargetSessionLogManager.instance.saveSession(
        analysis: makeAnalysis(),
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        firearmId: '',
        firearmLabel: 'second',
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
      );

      final sessions = await TargetSessionLogManager.instance.loadSessions();
      expect(sessions.length, 2);
      // Newest first → 'second' should be at index 0.
      expect(sessions.first.firearmLabel, 'second');
      expect(sessions.last.firearmLabel, 'first');
    });

    test('deleteSession removes the row', () async {
      final analysis = svc.analyze(
        shots: [ShotImpact(pixel: const Offset(0, 0))],
        pxPerMm: 1.0,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
      );
      final id = await TargetSessionLogManager.instance.saveSession(
        analysis: analysis,
        distance: 100,
        distanceUnit: DistanceUnit.yards,
        angularUnit: AngularUnit.moa,
        clickValue: 0.25,
        firearmId: '',
        firearmLabel: 'doomed',
        suggestedUpClicks: 0,
        suggestedRightClicks: 0,
      );
      expect(id, isNotNull);
      final deleted =
          await TargetSessionLogManager.instance.deleteSession(id!);
      expect(deleted, isTrue);
      final sessions = await TargetSessionLogManager.instance.loadSessions();
      expect(sessions, isEmpty);
    });

    test('loadSessions returns empty list when no rows exist', () async {
      final sessions = await TargetSessionLogManager.instance.loadSessions();
      expect(sessions, isEmpty);
    });
  });
}
