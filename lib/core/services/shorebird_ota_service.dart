import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Shorebird Code Push — over-the-air Dart-code updates.
///
/// Lets a Dart-only fix reach installed builds without a Play Store review
/// round-trip, which is the point of wiring it in ahead of the v22+ patch
/// cadence. Nothing here changes the shipped artifact: the updater reports
/// `isAvailable == false` in any build produced by `flutter build` /
/// `flutter run`, so normal builds behave exactly as before. Only a build
/// produced by `shorebird release` carries the Shorebird engine and can
/// install a patch.
///
/// The updater NEVER gates startup. `checkForUpdate()` makes a network call
/// that can take a long time; awaiting it in `initState` is the documented
/// way to leave the user staring at the splash screen, so every call here is
/// fire-and-forget with its own timeout and error handling.
class ShorebirdOtaService {
  ShorebirdOtaService._();
  static final ShorebirdOtaService instance = ShorebirdOtaService._();

  /// How long a check / download may run before it is abandoned. A patch is a
  /// background nicety — it must never hold a resource indefinitely.
  static const Duration checkTimeout = Duration(seconds: 15);
  static const Duration updateTimeout = Duration(minutes: 2);

  /// Test seam: overrides the updater so the OTA flow is exercisable without
  /// the Shorebird engine.
  @visibleForTesting
  static ShorebirdUpdater? updaterForTesting;

  /// Test seam: forces `isAvailable` for a test that wants to exercise the
  /// "engine present" path on a plain `flutter test` host.
  @visibleForTesting
  static bool? availableForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    updaterForTesting = null;
    availableForTesting = null;
  }

  ShorebirdUpdater get _updater => updaterForTesting ?? ShorebirdUpdater();

  /// Whether this build can install OTA patches. False for every normal
  /// `flutter build` / `flutter run` artifact and for web. Never throws.
  bool get isAvailable {
    final forced = availableForTesting;
    if (forced != null) return forced;
    try {
      return _updater.isAvailable;
    } catch (e) {
      debugPrint('ShorebirdOtaService: isAvailable probe failed: $e');
      return false;
    }
  }

  /// The currently installed patch number, or null when none is installed /
  /// the updater is unavailable. Never throws.
  Future<int?> currentPatchNumber() async {
    if (!isAvailable) return null;
    try {
      final patch = await _updater.readCurrentPatch().timeout(checkTimeout);
      return patch?.number;
    } catch (e) {
      debugPrint('ShorebirdOtaService: readCurrentPatch failed: $e');
      return null;
    }
  }

  /// Checks for a patch and, when one is available, downloads it so it takes
  /// effect on the next launch.
  ///
  /// Intended to be called fire-and-forget from app startup — it is bounded by
  /// [checkTimeout] / [updateTimeout] and swallows every failure (an offline
  /// device, a missing engine, or a download error must never affect the
  /// user's session). Returns the observed [UpdateStatus], or null when the
  /// updater is unavailable / the check could not complete.
  Future<UpdateStatus?> checkAndDownload({UpdateTrack? track}) async {
    if (!isAvailable) return null;
    try {
      final status =
          await _updater.checkForUpdate(track: track).timeout(checkTimeout);
      debugPrint('ShorebirdOtaService: update status = ${status.name}');
      if (status == UpdateStatus.outdated) {
        try {
          await _updater.update(track: track).timeout(updateTimeout);
          debugPrint('ShorebirdOtaService: patch downloaded; applies on restart');
        } catch (e) {
          debugPrint('ShorebirdOtaService: update failed: $e');
        }
      }
      return status;
    } catch (e) {
      debugPrint('ShorebirdOtaService: checkForUpdate failed: $e');
      return null;
    }
  }

  /// Fire-and-forget startup hook.
  ///
  /// Called from `main()` AFTER the first frame so the network check can never
  /// delay the splash screen. Errors are already contained inside
  /// [checkAndDownload]; the `unawaited` here is the whole point.
  void scheduleStartupCheck() {
    if (!isAvailable) {
      debugPrint(
        'ShorebirdOtaService: updater unavailable in this build '
        '(expected for flutter build/run) — skipping OTA check.',
      );
      return;
    }
    unawaited(checkAndDownload());
  }
}
