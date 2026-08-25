import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/services/device_fingerprint_service.dart';

/// Tests for the device-level trial-abuse prevention fingerprint service.
///
/// The plugin/platform call is exercised via the
/// `fingerprintResolverForTesting` seam, so the test host never touches
/// `device_info_plus` native channels — identical pattern to the project's
/// other service seams. The stamp write seam intercepts the Firestore merge,
/// so no Firebase app is required.
void main() {
  setUp(DeviceFingerprintService.resetTestSeams);
  tearDown(DeviceFingerprintService.resetTestSeams);

  group('DeviceFingerprintService.computeFingerprint', () {
    test('returns the resolver fingerprint when a seam is injected', () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => 'fp-hash-abc';
      expect(
        await DeviceFingerprintService.instance.computeFingerprint(),
        'fp-hash-abc',
      );
    });

    test(
        'on test hosts (no Android/iOS plugin channel) the production path '
        'resolves to null', () async {
      // On a desktop/flutter-test host, Platform.isAndroid/.isIOS are both
      // false, so the fingerprint is unavailable → null (fail-closed on the
      // backend treats missing fingerprints as a block, by design).
      expect(
        await DeviceFingerprintService.instance.computeFingerprint(),
        isNull,
      );
    });

    test('a null resolver yields null (unavailable on this device)', () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => null;
      expect(
        await DeviceFingerprintService.instance.computeFingerprint(),
        isNull,
      );
    });

    test('currentFingerprint static wrapper delegates to the singleton',
        () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => 'fp-static';
      expect(
        await DeviceFingerprintService.currentFingerprint(),
        'fp-static',
      );
    });
  });

  group('DeviceFingerprintService.stampDeviceFingerprint', () {
    test('merges the fingerprint onto users/{uid} via the write seam',
        () async {
      final stamps = <Map<String, String>>[];
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => 'fp-123';
      DeviceFingerprintService.stampWriterForTesting = (uid, fp) async {
        stamps.add({'uid': uid, 'fp': fp});
      };
      await DeviceFingerprintService.instance
          .stampDeviceFingerprint('user-1');
      expect(stamps, [
        {'uid': 'user-1', 'fp': 'fp-123'}
      ]);
    });

    test('skips the Firestore write when the fingerprint is unavailable',
        () async {
      var called = false;
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => null;
      DeviceFingerprintService.stampWriterForTesting = (uid, fp) async {
        called = true;
      };
      await DeviceFingerprintService.instance.stampDeviceFingerprint('user-1');
      expect(called, isFalse);
    });

    test('skips the Firestore write for empty user ids', () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => 'fp-123';
      var called = false;
      DeviceFingerprintService.stampWriterForTesting = (uid, fp) async {
        called = true;
      };
      await DeviceFingerprintService.instance.stampDeviceFingerprint('   ');
      expect(called, isFalse);
    });

    test('an empty resolver fingerprint never stamps', () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => '';
      var called = false;
      DeviceFingerprintService.stampWriterForTesting = (uid, fp) async {
        called = true;
      };
      await DeviceFingerprintService.instance.stampDeviceFingerprint('user-1');
      expect(called, isFalse);
    });

    test('a throwing resolver seam resolves to null (never crashes)', () async {
      DeviceFingerprintService.fingerprintResolverForTesting =
          () async => throw StateError('plugin unavailable');
      expect(
        await DeviceFingerprintService.instance.computeFingerprint(),
        isNull,
      );
    });
  });
}
