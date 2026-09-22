import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/services/force_update_service.dart';

void main() {
  group('ForceUpdateService constants', () {
    test('Remote Config keys match the documented contract', () {
      expect(ForceUpdateService.minVersionCodeKey, 'min_required_version_code');
      expect(ForceUpdateService.forceUpdateMessageKey, 'force_update_message');
    });

    test('default min version code is 0 (never blocks)', () {
      expect(ForceUpdateService.defaultMinVersionCode, 0);
    });

    test('default message mentions the update requirement', () {
      final msg = ForceUpdateService.defaultForceUpdateMessage;
      expect(msg, contains('critical update'));
      expect(msg, contains('JagSpoor'));
    });
  });

  group('shouldBlock (kill-switch gating rule)', () {
    test('blocks a build below the floor', () {
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 6,
          currentVersionCode: 5,
        ),
        isTrue,
      );
    });

    test('allows a build equal to the floor', () {
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 6,
          currentVersionCode: 6,
        ),
        isFalse,
      );
    });

    test('allows a build above the floor', () {
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 6,
          currentVersionCode: 7,
        ),
        isFalse,
      );
    });

    test('an unset floor (0) never blocks, even a versionCode of 0', () {
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 0,
          currentVersionCode: 0,
        ),
        isFalse,
      );
    });

    test('a negative floor never blocks (defensive fail-open)', () {
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: -1,
          currentVersionCode: 0,
        ),
        isFalse,
      );
    });

    test('a zero versionCode is blocked by a positive floor', () {
      // The buildNumber failed to parse (int.tryParse -> null -> 0); treat it
      // as the oldest possible build rather than silently skipping the gate.
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 1,
          currentVersionCode: 0,
        ),
        isTrue,
      );
    });

    test('mirrors the current v1.0.9 / versionCode 9 build', () {
      // Shipped build (versionCode 9) vs a future kill-switch floor.
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 10,
          currentVersionCode: 9,
        ),
        isTrue,
      );
      expect(
        ForceUpdateService.shouldBlock(
          minVersionCode: 9,
          currentVersionCode: 9,
        ),
        isFalse,
      );
    });
  });

  group('ForceUpdateDecision', () {
    test('allow carries the fail-open defaults', () {
      const decision = ForceUpdateDecision.allow;
      expect(decision.needsUpdate, isFalse);
      expect(decision.message, ForceUpdateService.defaultForceUpdateMessage);
      expect(decision.minVersionCode, ForceUpdateService.defaultMinVersionCode);
      expect(decision.currentVersionCode, 0);
    });

    test('a blocking decision exposes both version codes + the message', () {
      const decision = ForceUpdateDecision(
        needsUpdate: true,
        message: 'Please update to continue hunting.',
        minVersionCode: 8,
        currentVersionCode: 6,
      );
      expect(decision.needsUpdate, isTrue);
      expect(decision.minVersionCode, 8);
      expect(decision.currentVersionCode, 6);
      expect(decision.message, contains('update'));
    });
  });

  group('evaluate (fail-open contract)', () {
    test('resolves without throwing when Firebase is uninitialised', () async {
      // No Firebase.initializeApp() in the test process, so Remote Config
      // raises [core/no-app]. The service must swallow it and fail open so a
      // broken/absent Remote Config can never lock users out of the app.
      final decision = await ForceUpdateService.evaluate();
      expect(decision.needsUpdate, isFalse);
    });

    test('shouldForceUpdate returns false rather than throwing', () async {
      expect(await ForceUpdateService.shouldForceUpdate(), isFalse);
    });
  });
}