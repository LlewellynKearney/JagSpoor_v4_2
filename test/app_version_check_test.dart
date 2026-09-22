// Tests for the Firestore control-plane forced-update gate
// (`lib/services/app_version_check.dart`).
//
//  - `shouldForceUpdate`: the pure gating rule (doc existence, the
//    `force_update` flag, the version floor and the installed build number) —
//    unit-testable without a Firestore app or a widget tree.
//  - `isUpdateRequired`: the fail-open contract, proven live against an
//    uninitialised Firebase (`[core/no-app]`), which must resolve `false`
//    rather than throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/services/app_version_check.dart';

void main() {
  group('AppVersionCheck constants', () {
    test('config path is the admin_config control-plane doc', () {
      expect(AppVersionCheck.configPath, 'admin_config/app_version');
    });

    test('Play Store URL targets the production application id', () {
      expect(AppVersionCheck.playStoreUrl, contains('za.co.jagspoor.app'));
      expect(AppVersionCheck.playStoreUrl, startsWith('https://'));
    });

    test('default message is user-facing copy', () {
      expect(AppVersionCheck.defaultMessage, isNotEmpty);
      expect(AppVersionCheck.defaultMessage, contains('update'));
    });
  });

  group('shouldForceUpdate (gating rule)', () {
    test('a missing doc never blocks', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: false,
          minRequiredVersion: 9,
          forceUpdate: true,
          currentBuildNumber: 8,
        ),
        isFalse,
      );
    });

    test('force_update == false never blocks', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 9,
          forceUpdate: false,
          currentBuildNumber: 8,
        ),
        isFalse,
      );
    });

    test('an unset floor (0) never blocks (defensive fail-open)', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 0,
          forceUpdate: true,
          currentBuildNumber: 0,
        ),
        isFalse,
      );
    });

    test('a negative floor never blocks (defensive fail-open)', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: -1,
          forceUpdate: true,
          currentBuildNumber: 0,
        ),
        isFalse,
      );
    });

    test('a build below the floor is blocked', () {
      // The v8 closed-test build vs the v9 floor.
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 9,
          forceUpdate: true,
          currentBuildNumber: 8,
        ),
        isTrue,
      );
    });

    test('the shipped v9 build satisfies the v9 floor', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 9,
          forceUpdate: true,
          currentBuildNumber: 9,
        ),
        isFalse,
      );
    });

    test('a build above the floor is allowed', () {
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 9,
          forceUpdate: true,
          currentBuildNumber: 10,
        ),
        isFalse,
      );
    });

    test('an unparsed build number (0) is blocked by a positive floor', () {
      // `int.tryParse(packageInfo.buildNumber)` returned null -> 0; treat the
      // build as the oldest possible rather than silently skipping the gate.
      expect(
        AppVersionCheck.shouldForceUpdate(
          docExists: true,
          minRequiredVersion: 1,
          forceUpdate: true,
          currentBuildNumber: 0,
        ),
        isTrue,
      );
    });
  });

  group('isUpdateRequired (fail-open contract)', () {
    testWidgets(
      'resolves false rather than throwing when Firebase is uninitialised',
      (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        // No Firebase.initializeApp() has run in this test host, so the
        // Firestore read throws `[core/no-app]`; the gate must swallow it and
        // report "no update required" (never lock the user out).
        final blocked = await AppVersionCheck.isUpdateRequired(ctx);
        expect(blocked, isFalse);
      },
    );
  });
}
