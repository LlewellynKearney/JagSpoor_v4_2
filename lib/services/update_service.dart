import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
///  * A build installed outside Google Play (e.g. `flutter run`, a sideloaded
///    APK or an emulator) makes Play Core reject the query with
///    `ERROR_APP_NOT_OWNED` (numeric code `-10`): the calling app was not
///    installed from the Play Store, so it has no update to manage. That is a
///    local/dev-build condition, not an error — it is detected and skipped
///    with a "Local build - skipping update check" log so it can never block
///    the UI.
class UpdateService {
  const UpdateService._();

  /// Play Core's `ERROR_APP_NOT_OWNED` code. Surfaced by the `in_app_update`
  /// plugin either in the error message string or as the numeric
  /// `PlatformException` code (`-10`), depending on the plugin build.
  static const String appNotOwnedErrorCode = 'ERROR_APP_NOT_OWNED';

  /// Whether [error] represents Play Core's `ERROR_APP_NOT_OWNED` (-10),
  /// i.e. the app was installed outside the Play Store. Matched against the
  /// message, the exception `code` and the `details` so every plugin spelling
  /// is covered.
  static bool isAppNotOwned(Object error) {
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      final details = '${error.details}'.toLowerCase();
      if (code == '-10' || code == 'app_not_owned') return true;
      if (message.contains('app_not_owned') ||
          message.contains('error_app_not_owned')) {
        return true;
      }
      if (details.contains('app_not_owned') ||
          details.contains('error_app_not_owned') ||
          details.contains('-10')) {
        return true;
      }
    }
    final text = error.toString().toLowerCase();
    return text.contains('error_app_not_owned') ||
        text.contains('app_not_owned') ||
        text.contains('app not owned');
  }

  /// Asks the Play Store for an available update and forces it when allowed.
  ///
  /// Safe to call unconditionally — never throws. Intended to be invoked once,
  /// shortly after the first frame, so the Play dialog is not racing the
  /// app's own startup navigation.
  static Future<void> checkForImmediateUpdate() async {
    // Local/debug builds are not distributed through Google Play, so an update
    // check is meaningless and Play Core rejects it (ERROR_APP_NOT_OWNED).
    // Skip outright rather than relying on the catch below.
    if (kDebugMode) {
      debugPrint('Local build - skipping update check');
      return;
    }

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
      // A build installed outside Google Play (`flutter run`, sideloaded APK,
      // emulator) makes Play Core reject the query with ERROR_APP_NOT_OWNED.
      // That is expected for a local build — log and return without blocking
      // the UI.
      if (isAppNotOwned(e)) {
        debugPrint('Local build - skipping update check');
        return;
      }
      // Distribution channel (sideloaded APK / emulator without Play), a
      // non-Play install, or a transient Play services error. Never fatal:
      // the user simply continues on the installed build.
      debugPrint('Update check failed: $e');
    }
  }
}