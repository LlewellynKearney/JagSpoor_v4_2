import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play in-app update gate.
///
/// Drives the Play Core AppUpdateManager through the `in_app_update` plugin:
/// asks the Play Store whether a newer build is available for this package and,
/// when one is, forces the user onto it via an **immediate** update.
///
/// Why an immediate update: the Play Store only allows one in-app update
/// request per app process, so there is no value in asking for a *flexible*
/// update first — the user would have to restart before the result is applied
/// and the second call would be a no-op. We therefore request the immediate
/// flow, which Play renders as a full-screen blocking "Update" dialog.
///
/// The flexible path is retained as a **fallback** for the (unusual) case where
/// the Play Store reports an update as available but refuses the immediate
/// flow. It applies the download and then completes it, which surfaces Play's
/// own "restart to apply" prompt.
///
/// IMPORTANT — Android/Play constraints:
///  * Only functional for builds installed by Google Play. Sideloaded debug
///    APKs report [UpdateAvailability.updateNotAvailable], and Play services
///    throw if the calling app was not installed from the Play Store. Every
///    failure is swallowed (logged via [debugPrint]) so a distribution-channel
///    quirk can never block app startup.
///  * A newer `versionCode` must exist on the Play track under test. An
///    installed build that already matches the store sees "no update".
///  * On iOS (and desktop/web) the plugin has no implementation; the call is
///    skipped outright so no platform exception is raised.
class UpdateService {
  const UpdateService._();

  /// Asks the Play Store for an available update and forces it when allowed.
  ///
  /// Safe to call unconditionally — never throws. Intended to be invoked once,
  /// shortly after the first frame, so the Play dialog is not racing the
  /// app's own startup navigation.
  static Future<void> checkForImmediateUpdate() async {
    // Play in-app updates are Android-only. Skip everywhere else rather than
    // letting the plugin raise a MissingPluginException.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      debugPrint(
        'In-app update check: availability=${info.updateAvailability} '
        'immediate=${info.immediateUpdateAllowed} '
        'flexible=${info.flexibleUpdateAllowed}',
      );

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      if (info.immediateUpdateAllowed) {
        // Blocks the UI with the Play update dialog; resolves only once the
        // user has updated (app restarts) or dismissed it where permitted.
        final result = await InAppUpdate.performImmediateUpdate();
        debugPrint('Immediate update result: $result');
        if (result != AppUpdateResult.success) {
          debugPrint(
            'Immediate update not applied ($result). If this is a sideloaded '
            'or non-Play install the update flow is unavailable.',
          );
        }
        return;
      }

      if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        debugPrint('Flexible update started: $result');
        if (result != AppUpdateResult.success) {
          debugPrint('Flexible update not started ($result).');
          return;
        }
        // Installs the update downloaded by startFlexibleUpdate. Play takes
        // over and restarts the app, so nothing after this is guaranteed to run.
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      // Distribution channel (sideloaded APK / emulator without Play), a
      // non-Play install, or a transient Play services error. Never fatal:
      // the user simply continues on the installed build.
      debugPrint('Update check failed: $e');
    }
  }
}