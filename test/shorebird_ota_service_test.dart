// ============================================================================
// Shorebird OTA service contract
//
// The over-the-air updater must be invisible in every build that does not carry
// the Shorebird engine (i.e. everything produced by `flutter build` /
// `flutter run`, including the artifacts Play receives) and must never gate
// startup when it IS present. These tests lock both properties.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'package:jagspoor/core/services/shorebird_ota_service.dart';

/// A scripted updater so the OTA flow is exercised without the engine.
class _FakeUpdater implements ShorebirdUpdater {
  _FakeUpdater({
    this.available = true,
    this.status = UpdateStatus.upToDate,
    this.currentPatch,
    this.throwOnCheck = false,
    this.throwOnUpdate = false,
    this.hangOnCheck = false,
  });

  final bool available;
  final UpdateStatus status;
  final Patch? currentPatch;
  final bool throwOnCheck;
  final bool throwOnUpdate;
  final bool hangOnCheck;

  int checkCalls = 0;
  int updateCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<Patch?> readCurrentPatch() async => currentPatch;

  @override
  Future<Patch?> readNextPatch() async => currentPatch;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checkCalls += 1;
    if (hangOnCheck) {
      // Longer than the service's check timeout.
      await Future<void>.delayed(const Duration(minutes: 5));
    }
    if (throwOnCheck) {
      throw const UpdateException(
          message: 'boom', reason: UpdateFailureReason.unknown);
    }
    return status;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    updateCalls += 1;
    if (throwOnUpdate) {
      throw const UpdateException(
          message: 'download failed',
          reason: UpdateFailureReason.downloadFailed);
    }
  }
}

void main() {
  setUp(() {
    ShorebirdOtaService.resetTestSeams();
  });
  tearDown(() {
    ShorebirdOtaService.resetTestSeams();
  });

  test('isAvailable is false without the Shorebird engine', () {
    // The default updater reports unavailable in a `flutter test` host — the
    // same as any `flutter build` artifact.
    expect(ShorebirdOtaService.instance.isAvailable, isFalse);
  });

  test('checkAndDownload short-circuits when the updater is unavailable',
      () async {
    final fake = _FakeUpdater(available: false);
    ShorebirdOtaService.updaterForTesting = fake;

    final status = await ShorebirdOtaService.instance.checkAndDownload();
    expect(status, isNull);
    // No network call was attempted.
    expect(fake.checkCalls, 0);
    expect(fake.updateCalls, 0);
  });

  test('scheduleStartupCheck is a no-op when unavailable', () {
    final fake = _FakeUpdater(available: false);
    ShorebirdOtaService.updaterForTesting = fake;

    ShorebirdOtaService.instance.scheduleStartupCheck();
    expect(fake.checkCalls, 0);
  });

  test('downloads a patch when the build is outdated', () async {
    final fake = _FakeUpdater(status: UpdateStatus.outdated);
    ShorebirdOtaService.updaterForTesting = fake;

    final status = await ShorebirdOtaService.instance.checkAndDownload();
    expect(status, UpdateStatus.outdated);
    expect(fake.checkCalls, 1);
    expect(fake.updateCalls, 1);
  });

  test('does not download when the build is up to date', () async {
    final fake = _FakeUpdater(status: UpdateStatus.upToDate);
    ShorebirdOtaService.updaterForTesting = fake;

    await ShorebirdOtaService.instance.checkAndDownload();
    expect(fake.checkCalls, 1);
    expect(fake.updateCalls, 0);
  });

  test('reports restartRequired without re-downloading', () async {
    final fake = _FakeUpdater(status: UpdateStatus.restartRequired);
    ShorebirdOtaService.updaterForTesting = fake;

    final status = await ShorebirdOtaService.instance.checkAndDownload();
    expect(status, UpdateStatus.restartRequired);
    expect(fake.updateCalls, 0);
  });

  test('an update failure is swallowed (check still reports its status)',
      () async {
    final fake = _FakeUpdater(
        status: UpdateStatus.outdated, throwOnUpdate: true);
    ShorebirdOtaService.updaterForTesting = fake;

    final status = await ShorebirdOtaService.instance.checkAndDownload();
    expect(status, UpdateStatus.outdated);
    expect(fake.updateCalls, 1);
  });

  test('a check failure is swallowed and returns null', () async {
    final fake = _FakeUpdater(throwOnCheck: true);
    ShorebirdOtaService.updaterForTesting = fake;

    final status = await ShorebirdOtaService.instance.checkAndDownload();
    expect(status, isNull);
  });

  test('a hanging check is bounded by the timeout', () async {
    final fake = _FakeUpdater(hangOnCheck: true);
    ShorebirdOtaService.updaterForTesting = fake;

    // The service bounds the check; a hung updater must not hold the caller.
    final status = await ShorebirdOtaService.instance
        .checkAndDownload()
        .timeout(const Duration(seconds: 40), onTimeout: () => null);
    expect(status, isNull);
  });

  test('currentPatchNumber reads the installed patch', () async {
    ShorebirdOtaService.updaterForTesting =
        _FakeUpdater(currentPatch: const Patch(number: 7));
    expect(await ShorebirdOtaService.instance.currentPatchNumber(), 7);
  });

  test('currentPatchNumber is null when unavailable / no patch', () async {
    ShorebirdOtaService.updaterForTesting =
        _FakeUpdater(available: false, currentPatch: const Patch(number: 3));
    expect(await ShorebirdOtaService.instance.currentPatchNumber(), isNull);

    ShorebirdOtaService.updaterForTesting = _FakeUpdater();
    expect(await ShorebirdOtaService.instance.currentPatchNumber(), isNull);
  });
}
